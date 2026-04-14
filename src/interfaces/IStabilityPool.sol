// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStabilityPool {
    function sharePrice() external view returns (uint256);

    function deposit(uint256 amount) external returns (uint256 shares);

    function withdraw(
        uint256 shares
    ) external returns (uint256 hyUSDOut, uint256 xETHOut);

    function injectYield(uint256 hyUSDAmount) external;

    function drawdown(uint256 hyUSDToBurn, uint256 xETHToMint) external;

    function totalHyUSD() external view returns (uint256);

    function totalXETH() external view returns (uint256);

    function previewWithdrawHyUSD(uint256 shares) external view returns (uint256);
}
