// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILSTRateProvider
/// @notice Standard interface for an LST-specific ETH rate provider.
interface ILSTRateProvider {
    /// @notice Returns the LST token this provider serves.
    function lstToken() external view returns (address);

    /// @notice Returns ETH per 1 LST token in WAD.
    function getRate() external view returns (uint256 rate);
}
