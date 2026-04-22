// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IFeeController.sol";
import "../lst/ILSTOracle.sol";
import "./IPriceOracle.sol";
import "../stability/IStabilityPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBloomVault {
    error BloomVault__OnlyFactory();
    error BloomVault__OnlyOwnerFactory();
    error BloomVault__OnlyFeeRecipient();
    event BloomUSDMinted(address indexed user, address lst, uint256 lstIn, uint256 bloomUSDOut, uint256 fee);
    event BloomUSDRedeemed(address indexed user, address lst, uint256 bloomUSDIn, uint256 lstOut, uint256 fee);
    event XNativeMinted(address indexed user, address lst, uint256 lstIn, uint256 xNativeOut, uint256 fee);
    event XNativeRedeemed(address indexed user, address lst, uint256 xNativeIn, uint256 lstOut, uint256 fee);
    event YieldHarvested(uint256 nativeYield, uint256 bloomUSDMinted);
    event YieldSnapshotUpdated(address indexed lst, uint256 balance, uint256 rate);
    event DrawdownTriggered(uint256 cr, uint256 bloomUSDBurned, uint256 xNativeMinted);
    event LSTAdded(address lst);
    event LSTRemoved(address lst);

    function implementation() external view returns (address);

    function initialize() external;

    function getBloomUSD() external view returns (IERC20 bloomUSD);

    function getXNative() external view returns (IERC20 xNative);

    function getLSTOracle() external view returns (ILSTOracle lstOracle);

    function getPriceOracle() external view returns (IPriceOracle priceOracle);

    function getFeeController() external view returns (IFeeController feeController);

    function getStabilityPool() external view returns (IStabilityPool stabilityPool);

    function getTotalNative() external view returns (uint256 totalNative);

    function getNativePrice() external view returns (uint256 price);

    function getBloomUSDNavNative() external view returns (uint256);

    function getFixedReserve() external view returns (uint256);

    function getVariableReserve() external view returns (uint256 variableReserve, bool solvent);

    function getXNativeNavNative() external view returns (uint256);

    function getCollateralRatio() external view returns (uint256 cr);

    function getEffectiveLeverage() external view returns (uint256);

    function getProtocolState()
        external
        view
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
        );

    
    function mintBloomUSD(address lst, uint256 lstAmount, uint256 minBloomUSD) external returns (uint256 bloomUSDOut);

    function redeemBloomUSD(uint256 bloomUSDAmount, address lst, uint256 minLST) external returns (uint256 lstOut);

    function mintXNative(address lst, uint256 lstAmount, uint256 minXNative) external returns (uint256 xNativeOut);

    function redeemXNative(uint256 xNativeAmount, address lst, uint256 minLST) external returns (uint256 lstOut);

    function harvest() external;

    function triggerDrawdown() external;

    function addLST(address lst) external;

    function removeLST(address lst) external;

    function getLSTCount() external view returns (uint256);
}
