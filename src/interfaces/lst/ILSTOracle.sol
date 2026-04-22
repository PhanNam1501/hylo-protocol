// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILSTOracle
/// @notice Interface for fetching LST-to-Native rates.
interface ILSTOracle {
    /// @return rate Native per LST in WAD.
    function getLSTRate(address lst) external view returns (uint256 rate);
}
