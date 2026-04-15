// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPriceOracle
/// @notice Interface for ETH/USD price data.
interface IPriceOracle {
    /// @return price ETH price in USD with 8 decimals.
    /// @return updatedAt Last update timestamp.
    function getETHUSDPrice() external view returns (uint256 price, uint256 updatedAt);
}
