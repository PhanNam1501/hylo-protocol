// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILSTOracle
/// @notice Interface for fetching LST-to-ETH rates.
interface ILSTOracle {
    /// @return rate ETH per LST in WAD.
    function getLSTRate(address lst) external view returns (uint256 rate);
}
