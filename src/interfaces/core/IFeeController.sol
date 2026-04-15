// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeeController {
    enum StabilityMode {
        HEALTHY,
        MODE1,
        MODE2
    }

    function getMode(uint256 cr) external pure returns (StabilityMode);

    function getHyUSDMintFee(uint256 cr) external view returns (uint256);

    function getHyUSDRedeemFee(uint256 cr) external view returns (uint256);

    function getXETHMintFee(uint256 cr) external view returns (uint256);

    function getXETHRedeemFee(uint256 cr) external view returns (uint256);

    function applyFee(uint256 amount, uint256 feeBps) external pure returns (uint256 net, uint256 feeAmount);

    function setHealthyFees(uint256 mintHyUSD, uint256 redeemHyUSD, uint256 mintXETH, uint256 redeemXETH) external;
}
