// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../tokens/HyUSD.sol";
import "../tokens/XETH.sol";
import "../interfaces/lst/ILSTOracle.sol";
import "../interfaces/core/IPriceOracle.sol";
import "../core/FeeController.sol";
import "../stability/StabilityPool.sol";
import "../libraries/HyloMath.sol";

/// @title HyloVault
/// @notice Core vault for collateral, mint/redeem, harvest, and drawdown flows.
contract HyloVault is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using HyloMath for uint256;

    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    HyUSD public immutable hyUSD;
    XETH public immutable xETH;

    ILSTOracle public lstOracle;
    IPriceOracle public priceOracle;
    FeeController public feeController;
    StabilityPool public stabilityPool;

    address[] public lstAssets;
    mapping(address => bool) public isAcceptedLST;

    mapping(address => uint256) public lastSnapshotBalance;
    mapping(address => uint256) public lastSnapshotRate;

    address public treasury;

    uint256 public constant WAD = HyloMath.WAD;

    uint256 public constant CR_DRAWDOWN_TRIGGER = 1.30e18;
    uint256 public constant MAX_DRAWDOWN_FRACTION = 0.20e18;
    uint256 public constant CR_DRAWDOWN_TARGET = 1.40e18;

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
    event YieldSnapshotUpdated(address indexed lst, uint256 balance, uint256 rate);
    event DrawdownTriggered(
        uint256 cr,
        uint256 hyUSDBurned,
        uint256 xETHMinted
    );
    event LSTAdded(address lst);
    event LSTRemoved(address lst);

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

    /// @notice Returns total ETH value of all accepted LST collateral.
    function getTotalETH() public view returns (uint256 totalETH) {
        for (uint256 i = 0; i < lstAssets.length; i++) {
            address lst = lstAssets[i];
            uint256 balance = IERC20(lst).balanceOf(address(this));
            uint256 rate = lstOracle.getLSTRate(lst);
            totalETH += balance.wadMul(rate);
        }
    }

    /// @notice Returns ETH/USD price from the oracle.
    function getETHPrice() public view returns (uint256 price) {
        (price, ) = priceOracle.getETHUSDPrice();
    }

    /// @notice Returns hyUSD NAV denominated in ETH.
    function getHyUSDNavETH() public view returns (uint256) {
        return HyloMath.hyUSDNavInETH(getETHPrice());
    }

    /// @notice Returns current fixed reserve in ETH terms.
    function getFixedReserve() public view returns (uint256) {
        return hyUSD.totalSupply().wadMul(getHyUSDNavETH());
    }

    /// @notice Returns variable reserve and solvency status.
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

    /// @notice Returns xETH NAV denominated in ETH.
    function getXETHNavETH() public view returns (uint256) {
        uint256 supply = xETH.totalSupply();
        if (supply == 0) return WAD;
        (uint256 variableReserve, bool solvent) = getVariableReserve();
        if (!solvent || variableReserve == 0) return 0;
        return variableReserve.wadDiv(supply);
    }

    /// @notice Returns current collateral ratio.
    function getCollateralRatio() public view returns (uint256 cr) {
        uint256 totalETH = getTotalETH();
        uint256 fixedReserve = getFixedReserve();
        return HyloMath.collateralRatio(totalETH, fixedReserve);
    }

    /// @notice Returns current effective leverage.
    function getEffectiveLeverage() public view returns (uint256) {
        uint256 totalETH = getTotalETH();
        (uint256 variableReserve, ) = getVariableReserve();
        return HyloMath.effectiveLeverage(totalETH, variableReserve);
    }

    /// @notice Returns a full protocol state snapshot.
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

    /// @notice Deposits LST collateral and mints hyUSD.
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

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 lstRate = lstOracle.getLSTRate(lst);
        uint256 ethPrice = getETHPrice();
        uint256 ethValue = lstAmount.wadMul(lstRate);
        uint256 usdValue = HyloMath.ethToUSD(ethValue, ethPrice);

        uint256 fee = feeController.getHyUSDMintFee(cr);
        uint256 feeAmt = usdValue.wadMul(fee);
        hyUSDOut = usdValue - feeAmt;

        require(hyUSDOut >= minHyUSD, "Vault: slippage exceeded");
        require(hyUSDOut > 0, "Vault: zero out");

        IERC20(lst).safeTransferFrom(msg.sender, address(this), lstAmount);

        _updateSnapshotForLST(lst);

        hyUSD.mint(msg.sender, hyUSDOut);

        if (feeAmt > 0) hyUSD.mint(treasury, feeAmt);

        emit HyUSDMinted(msg.sender, lst, lstAmount, hyUSDOut, feeAmt);
    }

    /// @notice Burns hyUSD and redeems LST collateral.
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

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 ethPrice = getETHPrice();
        uint256 lstRate = lstOracle.getLSTRate(lst);

        uint256 fee = feeController.getHyUSDRedeemFee(cr);
        uint256 feeAmt = hyUSDAmount.wadMul(fee);
        uint256 netHyUSD = hyUSDAmount - feeAmt;

        uint256 ethNeeded = HyloMath.usdToETH(netHyUSD, ethPrice);
        lstOut = ethNeeded.wadDiv(lstRate);

        require(lstOut >= minLST, "Vault: slippage exceeded");
        require(
            IERC20(lst).balanceOf(address(this)) >= lstOut,
            "Vault: insufficient collateral"
        );

        hyUSD.burn(msg.sender, hyUSDAmount);

        if (feeAmt > 0) hyUSD.mint(treasury, feeAmt);

        IERC20(lst).safeTransfer(msg.sender, lstOut);

        _updateSnapshotForLST(lst);

        emit HyUSDRedeemed(msg.sender, lst, hyUSDAmount, lstOut, feeAmt);
    }

    /// @notice Deposits LST and mints xETH at current NAV.
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

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 lstRate = lstOracle.getLSTRate(lst);
        uint256 ethValue = lstAmount.wadMul(lstRate);

        uint256 fee = feeController.getXETHMintFee(cr);
        uint256 feeETH = ethValue.wadMul(fee);
        uint256 netETH = ethValue - feeETH;

        uint256 xETHNav = getXETHNavETH();
        require(xETHNav > 0, "Vault: xETH NAV is zero (protocol insolvent)");

        xETHOut = netETH.wadDiv(xETHNav);
        require(xETHOut >= minXETH, "Vault: slippage exceeded");
        require(xETHOut > 0, "Vault: zero out");

        IERC20(lst).safeTransferFrom(msg.sender, address(this), lstAmount);

        _updateSnapshotForLST(lst);

        xETH.mint(msg.sender, xETHOut);

        if (feeETH > 0) {
            uint256 feeLST = feeETH.wadDiv(lstRate);
            IERC20(lst).safeTransfer(treasury, feeLST);
        }

        emit XETHMinted(msg.sender, lst, lstAmount, xETHOut, feeETH);
    }

    /// @notice Burns xETH and redeems LST at current NAV.
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

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 xETHNav = getXETHNavETH();
        require(xETHNav > 0, "Vault: xETH NAV is zero");
        uint256 ethValue = xETHAmount.wadMul(xETHNav);

        uint256 fee = feeController.getXETHRedeemFee(cr);
        uint256 feeETH = ethValue.wadMul(fee);
        uint256 netETH = ethValue - feeETH;

        uint256 lstRate = lstOracle.getLSTRate(lst);
        lstOut = netETH.wadDiv(lstRate);

        require(lstOut >= minLST, "Vault: slippage exceeded");
        require(
            IERC20(lst).balanceOf(address(this)) >= lstOut,
            "Vault: insufficient collateral"
        );

        xETH.burn(msg.sender, xETHAmount);

        if (feeETH > 0) {
            uint256 feeLST = feeETH.wadDiv(lstRate);
            IERC20(lst).safeTransfer(treasury, feeLST);
        }

        IERC20(lst).safeTransfer(msg.sender, lstOut);

        _updateSnapshotForLST(lst);

        emit XETHRedeemed(msg.sender, lst, xETHAmount, lstOut, feeETH);
    }

    /// @notice Harvests accrued LST yield and injects it into the Stability Pool.
    function harvest() external onlyRole(HARVESTER_ROLE) {
        uint256 ethYield = _accruedEthYieldAndSyncAll();
        if (ethYield == 0) return;

        (uint256 variableReserve, bool solvent) = getVariableReserve();
        require(solvent, "Vault: insolvent, harvest blocked");

        if (ethYield > variableReserve / 10) {
            ethYield = variableReserve / 10;
        }

        uint256 ethPrice = getETHPrice();
        uint256 hyUSDToMint = HyloMath.ethToUSD(ethYield, ethPrice);

        if (hyUSDToMint == 0) return;

        hyUSD.mint(address(this), hyUSDToMint);
        IERC20(address(hyUSD)).approve(address(stabilityPool), hyUSDToMint);
        stabilityPool.injectYield(hyUSDToMint);

        emit YieldHarvested(ethYield, hyUSDToMint);
    }

    /// @notice Triggers Stability Pool drawdown when CR is below threshold.
    function triggerDrawdown() external nonReentrant {
        uint256 cr = getCollateralRatio();
        require(cr < CR_DRAWDOWN_TRIGGER, "Vault: CR above drawdown threshold");

        uint256 poolHyUSD = stabilityPool.totalHyUSD();
        require(poolHyUSD > 0, "Vault: Stability Pool empty");

        uint256 totalETH = getTotalETH();
        uint256 navETH = getHyUSDNavETH();
        uint256 hyUSDSupply = hyUSD.totalSupply();

        uint256 hyUSDNew = totalETH.wadDiv(CR_DRAWDOWN_TARGET).wadDiv(navETH);

        uint256 hyUSDToBurn;
        if (hyUSDNew >= hyUSDSupply) {
            return;
        } else {
            hyUSDToBurn = hyUSDSupply - hyUSDNew;
        }

        uint256 maxBurn = poolHyUSD.wadMul(MAX_DRAWDOWN_FRACTION);
        if (hyUSDToBurn > maxBurn) hyUSDToBurn = maxBurn;

        if (hyUSDToBurn > poolHyUSD) hyUSDToBurn = poolHyUSD;

        uint256 ethPrice = getETHPrice();
        uint256 xETHNavUSD = HyloMath.ethToUSD(getXETHNavETH(), ethPrice);
        require(xETHNavUSD > 0, "Vault: xETH price is zero");

        uint256 xETHToMint = hyUSDToBurn.wadDiv(xETHNavUSD);

        hyUSD.burn(address(stabilityPool), hyUSDToBurn);

        xETH.mint(address(this), xETHToMint);

        IERC20(address(xETH)).approve(address(stabilityPool), xETHToMint);
        stabilityPool.drawdown(hyUSDToBurn, xETHToMint);

        emit DrawdownTriggered(cr, hyUSDToBurn, xETHToMint);
    }

    /// @notice Syncs yield snapshot data for a single LST.
    function _syncSnapshotForLST(address lst) internal returns (uint256 ethYield) {
        uint256 lastBal = lastSnapshotBalance[lst];
        uint256 lastRate = lastSnapshotRate[lst];

        if (lastRate == 0) {
            _updateSnapshotForLST(lst);
            return 0;
        }

        uint256 rateNow = lstOracle.getLSTRate(lst);
        if (rateNow > lastRate && lastBal > 0) {
            ethYield = lastBal.wadMul(rateNow - lastRate);
        }

        lastSnapshotRate[lst] = rateNow;
        emit YieldSnapshotUpdated(lst, lastSnapshotBalance[lst], rateNow);
    }

    /// @notice Updates snapshot balance and rate for a single LST.
    function _updateSnapshotForLST(address lst) internal {
        uint256 balNow = IERC20(lst).balanceOf(address(this));
        uint256 rateNow = lstOracle.getLSTRate(lst);
        lastSnapshotBalance[lst] = balNow;
        lastSnapshotRate[lst] = rateNow;
        emit YieldSnapshotUpdated(lst, balNow, rateNow);
    }

    /// @notice Accrues and syncs yield snapshots for all LSTs.
    function _accruedEthYieldAndSyncAll() internal returns (uint256 ethYield) {
        for (uint256 i = 0; i < lstAssets.length; i++) {
            address lst = lstAssets[i];
            ethYield += _syncSnapshotForLST(lst);
            _updateSnapshotForLST(lst);
        }
    }

    function addLST(address lst) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isAcceptedLST[lst], "Vault: already added");
        isAcceptedLST[lst] = true;
        lstAssets.push(lst);
        _updateSnapshotForLST(lst);
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
