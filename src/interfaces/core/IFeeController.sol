// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeeController {
    enum StabilityMode {
        HEALTHY,
        MODE1,
        MODE2
    }

    function getMode(uint256 cr) external pure returns (StabilityMode);

    function getBloomUSDMintFee(uint256 cr) external view returns (uint256);

    function getBloomUSDRedeemFee(uint256 cr) external view returns (uint256);

    function getXNativeMintFee(uint256 cr) external view returns (uint256);

    function getXNativeRedeemFee(uint256 cr) external view returns (uint256);

    function applyFee(uint256 amount, uint256 feeBps) external pure returns (uint256 net, uint256 feeAmount);

    function setHealthyFees(uint256 mintBloomUSD, uint256 redeemBloomUSD, uint256 mintXNative, uint256 redeemXNative)
        external;
}
