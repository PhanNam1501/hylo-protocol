// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "../libraries/ReentrancyGuardUpgradeable.sol";
// import "@openzeppelin/contracts/utils/Pausable.sol";

import "../tokens/HyUSD.sol";
import "../tokens/XETH.sol";
import "../interfaces/lst/ILSTOracle.sol";
import "../interfaces/core/IPriceOracle.sol";
import "../interfaces/core/IFeeController.sol";
import "../interfaces/core/IBloomVault.sol";
import "../interfaces/core/IBloomVaultFactory.sol";
import "../interfaces/stability/IStabilityPool.sol";
import "../libraries/BloomMath.sol";
import "../libraries/Clone.sol";

/// @title BloomVault
/// @notice Core vault for collateral, mint/redeem, harvest, and drawdown flows.
contract BloomVault is ReentrancyGuardUpgradeable, IBloomVault, Clone {
    using SafeERC20 for IERC20;
    using BloomMath for uint256;

    address public immutable override implementation;
    IBloomVaultFactory private immutable _factory;

    address[] public lstAssets;
    mapping(address => bool) public isAcceptedLST;

    mapping(address => uint256) public lastSnapshotBalance;
    mapping(address => uint256) public lastSnapshotRate;

    uint256 public constant WAD = BloomMath.WAD;

    uint256 public constant CR_DRAWDOWN_TRIGGER = 1.3e18;
    uint256 public constant MAX_DRAWDOWN_FRACTION = 0.2e18;
    uint256 public constant CR_DRAWDOWN_TARGET = 1.4e18;

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    modifier onlyOwnerFactory() {
        if (msg.sender != _factory.owner()) revert BloomVault__OnlyOwnerFactory();
        _;
    }

    constructor(IBloomVaultFactory factory_) {
        _factory = factory_;
        implementation = address(this);

        _disableInitializers();
    }

    function initialize() external override onlyFactory initializer {
         __ReentrancyGuard_init();
    }

    function getBloomUSD() external pure override returns (IERC20 bloomUSD) {
        return _bloomUSD();
    }

    function getXNative() external pure override returns (IERC20 xNative) {
        return _xNative();
    }

    function getLSTOracle() external pure override returns (ILSTOracle lstOracle) {
        return _lstOracle();
    }

    function getPriceOracle() external pure override returns (IPriceOracle priceOracle) {
        return _priceOracle();
    }

    function getFeeController() external pure override returns (IFeeController feeController) {
        return _feeController();
    }

    function getStabilityPool() external pure override returns (IStabilityPool stabilityPool) {
        return _stabilityPool();
    }

    /// @notice Returns total Native value of all accepted LST collateral.
    function getTotalNative() public view override returns (uint256 totalNative) {
        for (uint256 i = 0; i < lstAssets.length; i++) {
            address lst = lstAssets[i];
            uint256 balance = IERC20(lst).balanceOf(address(this));
            uint256 rate = _lstOracle().getLSTRate(lst);
            totalNative += balance.wadMul(rate);
        }
    }

    /// @notice Returns Native/USD price from the oracle.
    function getNativePrice() public view override returns (uint256 price) {
        (price,) = _priceOracle().getNativeUSDPrice();
    }

    /// @notice Returns bloomUSD NAV denominated in Native.
    function getBloomUSDNavNative() public view override returns (uint256) {
        return BloomMath.bloomUSDNavInNative(getNativePrice());
    }

    /// @notice Returns current fixed reserve in Native terms.
    function getFixedReserve() public view override returns (uint256) {
        return _bloomUSD().totalSupply().wadMul(getBloomUSDNavNative());
    }

    /// @notice Returns variable reserve and solvency status.
    function getVariableReserve() public view override returns (uint256 variableReserve, bool solvent) {
        uint256 totalNative = getTotalNative();
        uint256 fixedReserve = getFixedReserve();
        if (totalNative >= fixedReserve) {
            variableReserve = totalNative - fixedReserve;
            solvent = true;
        } else {
            variableReserve = 0;
            solvent = false;
        }
    }

    /// @notice Returns xNative NAV denominated in Native.
    function getXNativeNavNative() public view override returns (uint256) {
        uint256 supply = _xNative().totalSupply();
        if (supply == 0) return WAD;
        (uint256 variableReserve, bool solvent) = getVariableReserve();
        if (!solvent || variableReserve == 0) return 0;
        return variableReserve.wadDiv(supply);
    }

    /// @notice Returns current collateral ratio.
    function getCollateralRatio() public view override returns (uint256 cr) {
        uint256 totalNative = getTotalNative();
        uint256 fixedReserve = getFixedReserve();
        return BloomMath.collateralRatio(totalNative, fixedReserve);
    }

    /// @notice Returns current effective leverage.
    function getEffectiveLeverage() public view override returns (uint256) {
        uint256 totalNative = getTotalNative();
        (uint256 variableReserve,) = getVariableReserve();
        return BloomMath.effectiveLeverage(totalNative, variableReserve);
    }

    /// @notice Returns a full protocol state snapshot.
    function getProtocolState()
        external
        view
        override
        returns (
            uint256 totalNative,
            uint256 nativePrice,
            uint256 bloomUSDNav,
            uint256 fixedReserve,
            uint256 variableReserve,
            uint256 xNativeNav,
            uint256 cr,
            uint256 effectiveLeverage,
            IFeeController.StabilityMode mode
        )
    {
        totalNative = getTotalNative();
        nativePrice = getNativePrice();
        bloomUSDNav = getBloomUSDNavNative();
        fixedReserve = getFixedReserve();
        (variableReserve,) = getVariableReserve();
        xNativeNav = getXNativeNavNative();
        cr = BloomMath.collateralRatio(totalNative, fixedReserve);
        effectiveLeverage = BloomMath.effectiveLeverage(totalNative, variableReserve);
        mode = _feeController().getMode(cr);
    }

    /// @notice Deposits LST collateral and mints bloomUSD.
    /// @param lst       Address of LST to deposit (must be in accepted basket)
    /// @param lstAmount Amount of LST (WAD)
    /// @param minBloomUSD  Slippage protection — min bloomUSD out
    function mintBloomUSD(address lst, uint256 lstAmount, uint256 minBloomUSD)
        external
        override
        nonReentrant
        returns (uint256 bloomUSDOut)
    {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(lstAmount > 0, "Vault: zero amount");

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 lstRate = _lstOracle().getLSTRate(lst);
        uint256 nativePrice = getNativePrice();
        uint256 nativeValue = lstAmount.wadMul(lstRate);
        uint256 usdValue = BloomMath.nativeToUSD(nativeValue, nativePrice);

        uint256 fee = _feeController().getBloomUSDMintFee(cr);
        uint256 feeAmt = usdValue.wadMul(fee);
        bloomUSDOut = usdValue - feeAmt;

        require(bloomUSDOut >= minBloomUSD, "Vault: slippage exceeded");
        require(bloomUSDOut > 0, "Vault: zero out");

        IERC20(lst).safeTransferFrom(msg.sender, address(this), lstAmount);

        _updateSnapshotForLST(lst);

        _bloomUSD().mint(msg.sender, bloomUSDOut);

        if (feeAmt > 0) _bloomUSD().mint(_factory.getFeeRecipient(), feeAmt);

        emit BloomUSDMinted(msg.sender, lst, lstAmount, bloomUSDOut, feeAmt);
    }

    /// @notice Burns bloomUSD and redeems LST collateral.
    /// @param bloomUSDAmount  Amount of bloomUSD to burn
    /// @param lst          Which LST to receive back
    /// @param minLST       Slippage protection
    function redeemBloomUSD(uint256 bloomUSDAmount, address lst, uint256 minLST)
        external
        override
        nonReentrant
        returns (uint256 lstOut)
    {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(bloomUSDAmount > 0, "Vault: zero amount");

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 nativePrice = getNativePrice();
        uint256 lstRate = _lstOracle().getLSTRate(lst);

        uint256 fee = _feeController().getBloomUSDRedeemFee(cr);
        uint256 feeAmt = bloomUSDAmount.wadMul(fee);
        uint256 netBloomUSD = bloomUSDAmount - feeAmt;

        uint256 nativeNeeded = BloomMath.usdToNative(netBloomUSD, nativePrice);
        lstOut = nativeNeeded.wadDiv(lstRate);

        require(lstOut >= minLST, "Vault: slippage exceeded");
        require(IERC20(lst).balanceOf(address(this)) >= lstOut, "Vault: insufficient collateral");

        _bloomUSD().burn(msg.sender, bloomUSDAmount);

        if (feeAmt > 0) _bloomUSD().mint(_factory.getFeeRecipient(), feeAmt);

        IERC20(lst).safeTransfer(msg.sender, lstOut);

        _updateSnapshotForLST(lst);

        emit BloomUSDRedeemed(msg.sender, lst, bloomUSDAmount, lstOut, feeAmt);
    }

    /// @notice Deposits LST and mints xNative at current NAV.
    /// @param lst       LST to deposit
    /// @param lstAmount Amount of LST
    /// @param minXNative   Slippage protection
    function mintXNative(address lst, uint256 lstAmount, uint256 minXNative)
        external
        override
        nonReentrant
        returns (uint256 xNativeOut)
    {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(lstAmount > 0, "Vault: zero amount");

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 lstRate = _lstOracle().getLSTRate(lst);
        uint256 nativeValue = lstAmount.wadMul(lstRate);

        uint256 fee = _feeController().getXNativeMintFee(cr);
        uint256 feeNative = nativeValue.wadMul(fee);
        uint256 netNative = nativeValue - feeNative;

        uint256 xNativeNav = getXNativeNavNative();
        require(xNativeNav > 0, "Vault: xNative NAV is zero (protocol insolvent)");

        xNativeOut = netNative.wadDiv(xNativeNav);
        require(xNativeOut >= minXNative, "Vault: slippage exceeded");
        require(xNativeOut > 0, "Vault: zero out");

        IERC20(lst).safeTransferFrom(msg.sender, address(this), lstAmount);

        _updateSnapshotForLST(lst);

        _xNative().mint(msg.sender, xNativeOut);

        if (feeNative > 0) {
            uint256 feeLST = feeNative.wadDiv(lstRate);
            IERC20(lst).safeTransfer(_factory.getFeeRecipient(), feeLST);
        }

        emit XNativeMinted(msg.sender, lst, lstAmount, xNativeOut, feeNative);
    }

    /// @notice Burns xNative and redeems LST at current NAV.
    /// @param xNativeAmount   Amount of xNative to burn
    /// @param lst          Which LST to receive
    /// @param minLST       Slippage protection
    function redeemXNative(uint256 xNativeAmount, address lst, uint256 minLST)
        external
        override
        nonReentrant
        returns (uint256 lstOut)
    {
        require(isAcceptedLST[lst], "Vault: LST not accepted");
        require(xNativeAmount > 0, "Vault: zero amount");

        _syncSnapshotForLST(lst);

        uint256 cr = getCollateralRatio();

        uint256 xNativeNav = getXNativeNavNative();
        require(xNativeNav > 0, "Vault: xNative NAV is zero");
        uint256 nativeValue = xNativeAmount.wadMul(xNativeNav);

        uint256 fee = _feeController().getXNativeRedeemFee(cr);
        uint256 feeNative = nativeValue.wadMul(fee);
        uint256 netNative = nativeValue - feeNative;

        uint256 lstRate = _lstOracle().getLSTRate(lst);
        lstOut = netNative.wadDiv(lstRate);

        require(lstOut >= minLST, "Vault: slippage exceeded");
        require(IERC20(lst).balanceOf(address(this)) >= lstOut, "Vault: insufficient collateral");

        _xNative().burn(msg.sender, xNativeAmount);

        if (feeNative > 0) {
            uint256 feeLST = feeNative.wadDiv(lstRate);
            IERC20(lst).safeTransfer(_factory.getFeeRecipient(), feeLST);
        }

        IERC20(lst).safeTransfer(msg.sender, lstOut);

        _updateSnapshotForLST(lst);

        emit XNativeRedeemed(msg.sender, lst, xNativeAmount, lstOut, feeNative);
    }

    /// @notice Harvests accrued LST yield and injects it into the Stability Pool.
    function harvest() external override nonReentrant {
        uint256 nativeYield = _accruedNativeYieldAndSyncAll();
        if (nativeYield == 0) return;

        (uint256 variableReserve, bool solvent) = getVariableReserve();
        require(solvent, "Vault: insolvent, harvest blocked");

        if (nativeYield > variableReserve / 10) {
            nativeYield = variableReserve / 10;
        }

        uint256 nativePrice = getNativePrice();
        uint256 bloomUSDToMint = BloomMath.nativeToUSD(nativeYield, nativePrice);

        if (bloomUSDToMint == 0) return;

        _bloomUSD().mint(address(this), bloomUSDToMint);
        IERC20(address(_bloomUSD())).approve(address(_stabilityPool()), bloomUSDToMint);
        _stabilityPool().injectYield(bloomUSDToMint);

        emit YieldHarvested(nativeYield, bloomUSDToMint);
    }

    /// @notice Triggers Stability Pool drawdown when CR is below threshold.
    function triggerDrawdown() external override nonReentrant {
        uint256 cr = getCollateralRatio();
        require(cr < CR_DRAWDOWN_TRIGGER, "Vault: CR above drawdown threshold");

        uint256 poolBloomUSD = _stabilityPool().totalBloomUSD();
        require(poolBloomUSD > 0, "Vault: Stability Pool empty");

        uint256 totalNative = getTotalNative();
        uint256 navNative = getBloomUSDNavNative();
        uint256 bloomUSDSupply = _bloomUSD().totalSupply();

        uint256 bloomUSDNew = totalNative.wadDiv(CR_DRAWDOWN_TARGET).wadDiv(navNative);

        uint256 bloomUSDToBurn;
        if (bloomUSDNew >= bloomUSDSupply) {
            return;
        } else {
            bloomUSDToBurn = bloomUSDSupply - bloomUSDNew;
        }

        uint256 maxBurn = poolBloomUSD.wadMul(MAX_DRAWDOWN_FRACTION);
        if (bloomUSDToBurn > maxBurn) bloomUSDToBurn = maxBurn;

        if (bloomUSDToBurn > poolBloomUSD) bloomUSDToBurn = poolBloomUSD;

        uint256 nativePrice = getNativePrice();
        uint256 xNativeNavUSD = BloomMath.nativeToUSD(getXNativeNavNative(), nativePrice);
        require(xNativeNavUSD > 0, "Vault: xNative price is zero");

        uint256 xNativeToMint = bloomUSDToBurn.wadDiv(xNativeNavUSD);

        _bloomUSD().burn(address(_stabilityPool()), bloomUSDToBurn);

        _xNative().mint(address(this), xNativeToMint);

        IERC20(address(_xNative())).approve(address(_stabilityPool()), xNativeToMint);
        _stabilityPool().drawdown(bloomUSDToBurn, xNativeToMint);

        emit DrawdownTriggered(cr, bloomUSDToBurn, xNativeToMint);
    }

    function addLST(address lst) external override onlyOwnerFactory {
        require(!isAcceptedLST[lst], "Vault: already added");
        isAcceptedLST[lst] = true;
        lstAssets.push(lst);
        _updateSnapshotForLST(lst);
        emit LSTAdded(lst);
    }

    function removeLST(address lst) external override onlyOwnerFactory {
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

    function getLSTCount() external view override returns (uint256) {
        return lstAssets.length;
    }

    function _bloomUSD() internal pure returns (BloomUSD) {
        return BloomUSD(_getArgAddress(0));
    }

    function _xNative() internal pure returns (XNative) {
        return XNative(_getArgAddress(20));
    }

    function _lstOracle() internal pure returns (ILSTOracle) {
        return ILSTOracle(_getArgAddress(40));
    }

    function _priceOracle() internal pure returns (IPriceOracle) {
        return IPriceOracle(_getArgAddress(60));
    }

    function _feeController() internal pure returns (IFeeController) {
        return IFeeController(_getArgAddress(80));
    }

    function _stabilityPool() internal pure returns (IStabilityPool) {
        return IStabilityPool(_getArgAddress(100));
    }

    /// @notice Syncs yield snapshot data for a single LST.
    function _syncSnapshotForLST(address lst) internal returns (uint256 nativeYield) {
        uint256 lastBal = lastSnapshotBalance[lst];
        uint256 lastRate = lastSnapshotRate[lst];

        if (lastRate == 0) {
            _updateSnapshotForLST(lst);
            return 0;
        }

        uint256 rateNow = _lstOracle().getLSTRate(lst);
        if (rateNow > lastRate && lastBal > 0) {
            nativeYield = lastBal.wadMul(rateNow - lastRate);
        }

        lastSnapshotRate[lst] = rateNow;
        emit YieldSnapshotUpdated(lst, lastSnapshotBalance[lst], rateNow);
    }

    /// @notice Updates snapshot balance and rate for a single LST.
    function _updateSnapshotForLST(address lst) internal {
        uint256 balNow = IERC20(lst).balanceOf(address(this));
        uint256 rateNow = _lstOracle().getLSTRate(lst);
        lastSnapshotBalance[lst] = balNow;
        lastSnapshotRate[lst] = rateNow;
        emit YieldSnapshotUpdated(lst, balNow, rateNow);
    }

    /// @notice Accrues and syncs yield snapshots for all LSTs.
    function _accruedNativeYieldAndSyncAll() internal returns (uint256 nativeYield) {
        for (uint256 i = 0; i < lstAssets.length; i++) {
            address lst = lstAssets[i];
            nativeYield += _syncSnapshotForLST(lst);
            _updateSnapshotForLST(lst);
        }
    }

    function _onlyFactory() private view {
        if (msg.sender != address(_factory)) revert BloomVault__OnlyFactory();
    }

}
