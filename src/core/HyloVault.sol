// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../tokens/HyUSD.sol";
import "../tokens/XETH.sol";
import "../interfaces/ILSTOracle.sol";
import "../interfaces/IPriceOracle.sol";
import "../core/FeeController.sol";
import "../stability/StabilityPool.sol";
import "../libraries/HyloMath.sol";

/// @title HyloVault
/// @notice Core vault implementing the Hylo Invariant for EVM/Base with ETH LSTs.
///
///         HYLO INVARIANT (adapted for ETH):
///           Collateral TVL (ETH) = Fixed Reserve + Variable Reserve
///           Fixed Reserve  = hyUSD supply × hyUSD NAV (ETH)
///                          = hyUSD supply / ETH price
///           Variable Reserve = TVL − Fixed Reserve
///           xETH price (ETH) = Variable Reserve / xETH supply
///
///         FLOW PER BLOCK:
///           1. getLSTRate(lst)        → ETH per LST (True Pricing, on-chain)
///           2. totalETH               = Σ (LST holdings × rate)
///           3. getETHUSDPrice()       → ETH/USD (only external oracle)
///           4. hyUSD NAV (ETH)        = 1 / ETH price (WAD)
///           5. Fixed Reserve          = hyUSD supply × NAV
///           6. Variable Reserve       = totalETH − fixedReserve
///           7. xETH NAV (ETH)         = variableReserve / xETH supply
///           8. CR                     = totalETH / fixedReserve
///           9. mode check             → fee adjustment / drawdown
///
///         SUPPORTED LSTs (Base mainnet):
///           wstETH: 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452
///           rETH:   not yet on Base (can add when deployed)
contract HyloVault is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using HyloMath for uint256;

    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // ─── Protocol Tokens ──────────────────────────────────────────────────
    HyUSD public immutable hyUSD;
    XETH public immutable xETH;

    // ─── External Dependencies ────────────────────────────────────────────
    ILSTOracle public lstOracle;
    IPriceOracle public priceOracle;
    FeeController public feeController;
    StabilityPool public stabilityPool;

    // ─── Collateral Basket ────────────────────────────────────────────────
    address[] public lstAssets;
    mapping(address => bool) public isAcceptedLST;

    // Snapshot of LST balances at last harvest (for yield detection)
    mapping(address => uint256) public lastHarvestBalance;

    // ─── Fee Treasury ─────────────────────────────────────────────────────
    address public treasury;

    // ─── Constants ────────────────────────────────────────────────────────
    uint256 public constant WAD = HyloMath.WAD;

    // Drawdown trigger: below this CR → Mode 2 → drawdown
    uint256 public constant CR_DRAWDOWN_TRIGGER = 1.30e18; // 130%
    // Max single drawdown = 20% of Stability Pool
    uint256 public constant MAX_DRAWDOWN_FRACTION = 0.20e18; // 20%
    // Minimum CR we target after drawdown
    uint256 public constant CR_DRAWDOWN_TARGET = 1.40e18; // 140%

    // ─── Events ───────────────────────────────────────────────────────────
    event HyUSDMinted(
        address indexed user,
        address lst,
        uint256 lstIn,
        uint256 hyUSDOut,
        uint256 fee
    );
    event HyUSDRedeemed(
        address indexed user,
        address lst,
        uint256 hyUSDIn,
        uint256 lstOut,
        uint256 fee
    );
    event XETHMinted(
        address indexed user,
        address lst,
        uint256 lstIn,
        uint256 xETHOut,
        uint256 fee
    );
    event XETHRedeemed(
        address indexed user,
        address lst,
        uint256 xETHIn,
        uint256 lstOut,
        uint256 fee
    );
    event YieldHarvested(uint256 ethYield, uint256 hyUSDMinted);
    event DrawdownTriggered(
        uint256 cr,
        uint256 hyUSDBurned,
        uint256 xETHMinted
    );
    event LSTAdded(address lst);
    event LSTRemoved(address lst);

    // ─── Constructor ──────────────────────────────────────────────────────

    constructor(
        address _hyUSD,
        address _xETH,
        address _lstOracle,
        address _priceOracle,
        address _feeController,
        address _stabilityPool,
        address _treasury,
        address _admin
    ) {
        hyUSD = HyUSD(_hyUSD);
        xETH = XETH(_xETH);
        lstOracle = ILSTOracle(_lstOracle);
        priceOracle = IPriceOracle(_priceOracle);
        feeController = FeeController(_feeController);
        stabilityPool = StabilityPool(_stabilityPool);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(HARVESTER_ROLE, _admin);
        _grantRole(GUARDIAN_ROLE, _admin);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  NAV CALCULATION ENGINE
    //  Implements the 10-step flow from Hylo docs exactly
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Step 1-2: Total ETH value of collateral pool
    ///         = Σ (LST balance × True LST Rate)
    function getTotalETH() public view returns (uint256 totalETH) {
        for (uint256 i = 0; i < lstAssets.length; i++) {
            address lst = lstAssets[i];
            uint256 balance = IERC20(lst).balanceOf(address(this));
            uint256 rate = lstOracle.getLSTRate(lst); // ETH per LST, WAD
            totalETH += balance.wadMul(rate);
        }
    }

    /// @notice Step 3: ETH/USD price from oracle
    function getETHPrice() public view returns (uint256 price) {
        (price, ) = priceOracle.getETHUSDPrice();
    }

    /// @notice Step 4: hyUSD NAV in ETH = 1 / ETH price
    ///         (1 hyUSD = $1 = 1/price ETH)
    function getHyUSDNavETH() public view returns (uint256) {
        return HyloMath.hyUSDNavInETH(getETHPrice());
    }

    /// @notice Step 5: Fixed Reserve = hyUSD supply × hyUSD NAV (ETH)
    function getFixedReserve() public view returns (uint256) {
        return hyUSD.totalSupply().wadMul(getHyUSDNavETH());
    }

    /// @notice Step 6: Variable Reserve = totalETH - fixedReserve
    function getVariableReserve()
        public
        view
        returns (uint256 variableReserve, bool solvent)
    {
        uint256 totalETH = getTotalETH();
        uint256 fixedReserve = getFixedReserve();
        if (totalETH >= fixedReserve) {
            variableReserve = totalETH - fixedReserve;
            solvent = true;
        } else {
            variableReserve = 0;
            solvent = false;
        }
    }

    /// @notice Step 7: xETH NAV in ETH = variableReserve / xETH supply
    function getXETHNavETH() public view returns (uint256) {
        uint256 supply = xETH.totalSupply();
        if (supply == 0) return WAD; // Bootstrap: 1 ETH per xETH
        (uint256 variableReserve, bool solvent) = getVariableReserve();
        if (!solvent || variableReserve == 0) return 0;
        return variableReserve.wadDiv(supply);
    }

    /// @notice Step 8: Collateral Ratio in WAD (1.5e18 = 150%)
    function getCollateralRatio() public view returns (uint256 cr) {
        uint256 totalETH = getTotalETH();
        uint256 fixedReserve = getFixedReserve();
        return HyloMath.collateralRatio(totalETH, fixedReserve);
    }

    /// @notice Step 9: Effective Leverage in WAD (2.5e18 = 2.5×)
    function getEffectiveLeverage() public view returns (uint256) {
        uint256 totalETH = getTotalETH();
        (uint256 variableReserve, ) = getVariableReserve();
        return HyloMath.effectiveLeverage(totalETH, variableReserve);
    }

    /// @notice Full protocol state snapshot (for frontend/keeper use)
    function getProtocolState()
        external
        view
        returns (
            uint256 totalETH,
            uint256 ethPrice,
            uint256 hyUSDNav,
            uint256 fixedReserve,
            uint256 variableReserve,
            uint256 xETHNav,
            uint256 cr,
            uint256 effectiveLeverage,
            FeeController.StabilityMode mode
        )
    {
        totalETH = getTotalETH();
        ethPrice = getETHPrice();
        hyUSDNav = getHyUSDNavETH();
        fixedReserve = getFixedReserve();
        (variableReserve, ) = getVariableReserve();
        xETHNav = getXETHNavETH();
        cr = HyloMath.collateralRatio(totalETH, fixedReserve);
        effectiveLeverage = HyloMath.effectiveLeverage(
            totalETH,
            variableReserve
        );
        mode = feeController.getMode(cr);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  MINT hyUSD
    //  User deposits LST → receives hyUSD at $1 peg
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Deposit LST collateral → receive hyUSD (stablecoin)
    ///
    ///         Hylo Invariant after mint:
    ///           TVL increases by lstAmount × rate
    ///           Fixed Reserve increases by same amount (new hyUSD backed 1:1)
    ///           Variable Reserve unchanged → xETH price unchanged
    ///           Effective Leverage INCREASES (TVL up, VR same)
    ///
    /// @param lst       Address of LST to deposit (must be in accepted basket)
    /// @param lstAmount Amount of LST (WAD)
    /// @param minHyUSD  Slippage protection — min hyUSD out
    function mintHyUSD(
        address lst,
        uint256 lstAmount,
        uint256 minHyUSD
    ) external nonReentrant whenNotPaused returns (uint256 hyUSDOut) {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(lstAmount > 0, "Vault: zero amount");

        uint256 cr = getCollateralRatio();

        // Step 1: Calculate USD value of deposited LST
        uint256 lstRate = lstOracle.getLSTRate(lst); // ETH per LST
        uint256 ethPrice = getETHPrice(); // USD per ETH (8 dec)
        uint256 ethValue = lstAmount.wadMul(lstRate); // ETH value (WAD)
        uint256 usdValue = HyloMath.ethToUSD(ethValue, ethPrice); // USD value (WAD)

        // Step 2: Apply mint fee (higher in Mode 1/2)
        uint256 fee = feeController.getHyUSDMintFee(cr);
        uint256 feeAmt = usdValue.wadMul(fee);
        hyUSDOut = usdValue - feeAmt;

        require(hyUSDOut >= minHyUSD, "Vault: slippage exceeded");
        require(hyUSDOut > 0, "Vault: zero out");

        // Step 3: Transfer LST in (collateral locked in vault)
        IERC20(lst).safeTransferFrom(msg.sender, address(this), lstAmount);

        // Step 4: Mint hyUSD to user
        hyUSD.mint(msg.sender, hyUSDOut);

        // Step 5: Fee → treasury (as hyUSD)
        if (feeAmt > 0) hyUSD.mint(treasury, feeAmt);

        emit HyUSDMinted(msg.sender, lst, lstAmount, hyUSDOut, feeAmt);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  REDEEM hyUSD
    //  User burns hyUSD → receives LST back at $1
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Burn hyUSD → receive LST collateral at $1 peg
    ///
    ///         After redeem:
    ///           hyUSD supply decreases → Fixed Reserve shrinks
    ///           TVL decreases → Variable Reserve unchanged → xETH price unchanged
    ///           CR adjusts (both TVL and Fixed Reserve decrease proportionally)
    ///
    /// @param hyUSDAmount  Amount of hyUSD to burn
    /// @param lst          Which LST to receive back
    /// @param minLST       Slippage protection
    function redeemHyUSD(
        uint256 hyUSDAmount,
        address lst,
        uint256 minLST
    ) external nonReentrant whenNotPaused returns (uint256 lstOut) {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(hyUSDAmount > 0, "Vault: zero amount");

        uint256 cr = getCollateralRatio();

        // hyUSD is $1 → convert to ETH → convert to LST
        uint256 ethPrice = getETHPrice();
        uint256 lstRate = lstOracle.getLSTRate(lst);

        // Apply redeem fee (lower in Mode 1/2 to encourage burning)
        uint256 fee = feeController.getHyUSDRedeemFee(cr);
        uint256 feeAmt = hyUSDAmount.wadMul(fee);
        uint256 netHyUSD = hyUSDAmount - feeAmt;

        // netHyUSD (USD, WAD) → ETH → LST
        uint256 ethNeeded = HyloMath.usdToETH(netHyUSD, ethPrice); // ETH WAD
        lstOut = ethNeeded.wadDiv(lstRate); // LST WAD

        require(lstOut >= minLST, "Vault: slippage exceeded");
        require(
            IERC20(lst).balanceOf(address(this)) >= lstOut,
            "Vault: insufficient collateral"
        );

        // Burn hyUSD from user
        hyUSD.burn(msg.sender, hyUSDAmount);

        // Fee as hyUSD to treasury (re-mint for fee portion)
        if (feeAmt > 0) hyUSD.mint(treasury, feeAmt);

        // Send LST to user
        IERC20(lst).safeTransfer(msg.sender, lstOut);

        emit HyUSDRedeemed(msg.sender, lst, hyUSDAmount, lstOut, feeAmt);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  MINT xETH
    //  User deposits LST → receives xETH (leveraged long)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Deposit LST → receive xETH at current NAV
    ///
    ///         After mint:
    ///           TVL increases, Variable Reserve increases
    ///           xETH supply increases proportionally → price unchanged
    ///           Effective Leverage DECREASES (risk diluted across more xETH)
    ///
    /// @param lst       LST to deposit
    /// @param lstAmount Amount of LST
    /// @param minXETH   Slippage protection
    function mintXETH(
        address lst,
        uint256 lstAmount,
        uint256 minXETH
    ) external nonReentrant whenNotPaused returns (uint256 xETHOut) {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(lstAmount > 0, "Vault: zero amount");

        uint256 cr = getCollateralRatio();

        // ETH value of deposited LST
        uint256 lstRate = lstOracle.getLSTRate(lst);
        uint256 ethValue = lstAmount.wadMul(lstRate); // ETH WAD

        // Apply mint fee
        uint256 fee = feeController.getXETHMintFee(cr);
        uint256 feeETH = ethValue.wadMul(fee);
        uint256 netETH = ethValue - feeETH;

        // xETH NAV tells us how much xETH per ETH deposited
        // xETHOut = netETH / xETH NAV (ETH)
        uint256 xETHNav = getXETHNavETH();
        require(xETHNav > 0, "Vault: xETH NAV is zero (protocol insolvent)");

        xETHOut = netETH.wadDiv(xETHNav);
        require(xETHOut >= minXETH, "Vault: slippage exceeded");
        require(xETHOut > 0, "Vault: zero out");

        // Lock collateral
        IERC20(lst).safeTransferFrom(msg.sender, address(this), lstAmount);

        // Mint xETH to user
        xETH.mint(msg.sender, xETHOut);

        // Fee portion: send LST to treasury (or convert — here we keep as LST)
        if (feeETH > 0) {
            uint256 feeLST = feeETH.wadDiv(lstRate);
            // Transfer fee LST to treasury
            IERC20(lst).safeTransfer(treasury, feeLST);
        }

        emit XETHMinted(msg.sender, lst, lstAmount, xETHOut, feeETH);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  REDEEM xETH
    //  User burns xETH → receives pro-rata Variable Reserve as LST
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Burn xETH → receive LST at current xETH NAV
    ///
    ///         After redeem:
    ///           xETH supply decreases, Variable Reserve decreases
    ///           xETH price unchanged, Effective Leverage INCREASES
    ///
    /// @param xETHAmount   Amount of xETH to burn
    /// @param lst          Which LST to receive
    /// @param minLST       Slippage protection
    function redeemXETH(
        uint256 xETHAmount,
        address lst,
        uint256 minLST
    ) external nonReentrant whenNotPaused returns (uint256 lstOut) {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(xETHAmount > 0, "Vault: zero amount");

        uint256 cr = getCollateralRatio();

        // ETH value of xETH being redeemed
        uint256 xETHNav = getXETHNavETH();
        require(xETHNav > 0, "Vault: xETH NAV is zero");
        uint256 ethValue = xETHAmount.wadMul(xETHNav);

        // Apply redeem fee (higher in Mode 1/2 to discourage xETH exit)
        uint256 fee = feeController.getXETHRedeemFee(cr);
        uint256 feeETH = ethValue.wadMul(fee);
        uint256 netETH = ethValue - feeETH;

        // Convert ETH → LST
        uint256 lstRate = lstOracle.getLSTRate(lst);
        lstOut = netETH.wadDiv(lstRate);

        require(lstOut >= minLST, "Vault: slippage exceeded");
        require(
            IERC20(lst).balanceOf(address(this)) >= lstOut,
            "Vault: insufficient collateral"
        );

        // Burn xETH
        xETH.burn(msg.sender, xETHAmount);

        // Fee to treasury
        if (feeETH > 0) {
            uint256 feeLST = feeETH.wadDiv(lstRate);
            IERC20(lst).safeTransfer(treasury, feeLST);
        }

        // Send LST to user
        IERC20(lst).safeTransfer(msg.sender, lstOut);

        emit XETHRedeemed(msg.sender, lst, xETHAmount, lstOut, feeETH);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  HARVEST — LST Staking Yield
    //  LST rates increase each epoch → TVL grows → mint hyUSD → inject into pool
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Harvest LST staking yield and distribute to Stability Pool.
    ///
    ///         How it works:
    ///           1. Compare current TVL vs last-harvest TVL
    ///           2. Excess = new LST yield (rate appreciation, not new deposits)
    ///           3. Mint equivalent hyUSD (backed by excess collateral)
    ///           4. Inject into Stability Pool → share price rises
    ///           5. hyUSD supply increases, but so does backing → invariant holds
    ///
    ///         Called by HARVESTER_ROLE (keeper bot, once per epoch ~8h or daily).
    function harvest() external onlyRole(HARVESTER_ROLE) {
        uint256 currentTVL = getTotalETH();
        uint256 fixedReserve = getFixedReserve();

        // Compute total TVL at last harvest using stored balances + current rates
        // (rates increased since last harvest → same LST balance = more ETH now)
        uint256 lastTVL = _computeLastHarvestTVL();

        if (currentTVL <= lastTVL) return; // No yield yet

        uint256 ethYield = currentTVL - lastTVL;

        // Sanity: don't harvest more than available variable reserve
        (uint256 variableReserve, bool solvent) = getVariableReserve();
        require(solvent, "Vault: insolvent, harvest blocked");

        // Only harvest the yield portion — don't eat into variable reserve
        if (ethYield > variableReserve / 10) {
            ethYield = variableReserve / 10; // Cap at 10% of VR per harvest
        }

        // Convert ETH yield → USD (hyUSD)
        uint256 ethPrice = getETHPrice();
        uint256 hyUSDToMint = HyloMath.ethToUSD(ethYield, ethPrice);

        if (hyUSDToMint == 0) return;

        // Mint and inject into Stability Pool
        hyUSD.mint(address(this), hyUSDToMint);
        IERC20(address(hyUSD)).approve(address(stabilityPool), hyUSDToMint);
        stabilityPool.injectYield(hyUSDToMint);

        // Update harvest checkpoint
        _updateHarvestCheckpoint();

        emit YieldHarvested(ethYield, hyUSDToMint);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  DRAWDOWN — Mode 2 Stability Mechanism
    //  CR < 130% → burn Stability Pool hyUSD → mint xETH into pool
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Trigger Stability Pool drawdown when CR < 130%.
    ///
    ///         Effect:
    ///           hyUSD supply ↓ → Fixed Reserve ↓ → CR numerically rises
    ///           xETH supply ↑ (minted into pool) → EL dilutes
    ///           Non-linear: each unit burned has increasing CR impact
    ///
    ///         Anyone can call this when CR < CR_DRAWDOWN_TRIGGER.
    ///         (Economic incentive: system health benefits all participants)
    function triggerDrawdown() external nonReentrant {
        uint256 cr = getCollateralRatio();
        require(cr < CR_DRAWDOWN_TRIGGER, "Vault: CR above drawdown threshold");

        uint256 poolHyUSD = stabilityPool.totalHyUSD();
        require(poolHyUSD > 0, "Vault: Stability Pool empty");

        // Calculate how much hyUSD to burn to reach CR target
        // CR = totalETH / (hyUSDSupply × navETH)
        // Target: CR = 1.40
        // Solve for hyUSDSupply_new:
        //   hyUSDSupply_new = totalETH / (target × navETH)
        //   hyUSD to burn = hyUSDSupply_current - hyUSDSupply_new

        uint256 totalETH = getTotalETH();
        uint256 navETH = getHyUSDNavETH();
        uint256 hyUSDSupply = hyUSD.totalSupply();

        // hyUSDNew = totalETH / (targetCR × navETH)
        // = totalETH × WAD / targetCR / navETH
        uint256 hyUSDNew = totalETH.wadDiv(CR_DRAWDOWN_TARGET).wadDiv(navETH);

        uint256 hyUSDToBurn;
        if (hyUSDNew >= hyUSDSupply) {
            return; // Already at target (rounding)
        } else {
            hyUSDToBurn = hyUSDSupply - hyUSDNew;
        }

        // Cap at MAX_DRAWDOWN_FRACTION of pool per call
        uint256 maxBurn = poolHyUSD.wadMul(MAX_DRAWDOWN_FRACTION);
        if (hyUSDToBurn > maxBurn) hyUSDToBurn = maxBurn;

        // Cap at actual pool balance
        if (hyUSDToBurn > poolHyUSD) hyUSDToBurn = poolHyUSD;

        // Calculate xETH to mint in exchange
        // xETH value = same USD value as hyUSD burned (1:1 economic exchange)
        // xETH amount = hyUSDToBurn (USD) / xETH price (USD)
        uint256 ethPrice = getETHPrice();
        uint256 xETHNavUSD = HyloMath.ethToUSD(getXETHNavETH(), ethPrice); // USD per xETH
        require(xETHNavUSD > 0, "Vault: xETH price is zero");

        uint256 xETHToMint = hyUSDToBurn.wadDiv(xETHNavUSD);

        // 1. Burn hyUSD from Stability Pool (vault has MINTER_ROLE)
        hyUSD.burn(address(stabilityPool), hyUSDToBurn);

        // 2. Mint xETH to this contract (vault has MINTER_ROLE on xETH)
        xETH.mint(address(this), xETHToMint);

        // 3. Approve and tell pool to account the drawdown
        IERC20(address(xETH)).approve(address(stabilityPool), xETHToMint);
        stabilityPool.drawdown(hyUSDToBurn, xETHToMint);

        uint256 newCR = getCollateralRatio();
        emit DrawdownTriggered(cr, hyUSDToBurn, xETHToMint);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  INTERNAL HELPERS
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Compute TVL using last-harvest LST balances + current rates
    ///         Difference vs current TVL = yield accrued since last harvest
    function _computeLastHarvestTVL() internal view returns (uint256 tvl) {
        for (uint256 i = 0; i < lstAssets.length; i++) {
            address lst = lstAssets[i];
            uint256 balance = lastHarvestBalance[lst];
            uint256 rate = lstOracle.getLSTRate(lst);
            tvl += balance.wadMul(rate);
        }
    }

    function _updateHarvestCheckpoint() internal {
        for (uint256 i = 0; i < lstAssets.length; i++) {
            address lst = lstAssets[i];
            lastHarvestBalance[lst] = IERC20(lst).balanceOf(address(this));
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  ADMIN
    // ─────────────────────────────────────────────────────────────────────

    function addLST(address lst) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isAcceptedLST[lst], "Vault: already added");
        isAcceptedLST[lst] = true;
        lstAssets.push(lst);
        lastHarvestBalance[lst] = IERC20(lst).balanceOf(address(this));
        emit LSTAdded(lst);
    }

    function removeLST(address lst) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isAcceptedLST[lst], "Vault: not in basket");
        isAcceptedLST[lst] = false;
        for (uint256 i = 0; i < lstAssets.length; i++) {
            if (lstAssets[i] == lst) {
                lstAssets[i] = lstAssets[lstAssets.length - 1];
                lstAssets.pop();
                break;
            }
        }
        emit LSTRemoved(lst);
    }

    function setTreasury(
        address _treasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "Vault: zero address");
        treasury = _treasury;
    }

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    function getLSTCount() external view returns (uint256) {
        return lstAssets.length;
    }
}
