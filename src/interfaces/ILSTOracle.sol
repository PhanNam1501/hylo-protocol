// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILSTOracle
/// @notice Returns the LST/ETH exchange rate directly from the LST contract
///         (mirrors Hylo's True LST Price: SOL in pool / LST supply)
///         No external oracle needed for LST pricing — only ETH/USD needs one.
interface ILSTOracle {
    /// @return rate WAD-scaled (1e18 = 1 ETH per LST)
    function getLSTRate(address lst) external view returns (uint256 rate);
}
