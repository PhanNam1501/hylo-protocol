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

    function withdraw(uint256 shares) external returns (uint256 bloomUSdOut, uint256 xNativeOut);

    function injectYield(uint256 bloomUSdAmount) external;

    function drawdown(uint256 bloomUSdToBurn, uint256 xNativeToMint) external;

    function totalBloomUSd() external view returns (uint256);

    function totalXNative() external view returns (uint256);

    function previewWithdrawBloomUSd(uint256 shares) external view returns (uint256);
}
