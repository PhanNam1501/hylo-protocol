// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

interface IStabilityPool {
    function sharePrice() external view returns (uint256);

    function deposit(uint256 amount) external returns (uint256 shares);

    function depositWithPermit2(
        uint160 amount,
        address owner,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature
    ) external returns (uint256 shares);

    function withdraw(uint256 shares) external returns (uint256 bloomUSDOut, uint256 xNativeOut);

    function injectYield(uint256 bloomUSDAmount) external;

    function drawdown(uint256 bloomUSDToBurn, uint256 xNativeToMint) external;

    function totalBloomUSD() external view returns (uint256);

    function totalXNative() external view returns (uint256);

    function previewWithdrawBloomUSD(uint256 shares) external view returns (uint256);
}
