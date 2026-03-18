// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPriceOracle
/// @notice ETH/USD price — the only external oracle Hylo needs
///         (mirrors Hylo's design: only 1 oracle, SOL/USD)
interface IPriceOracle {
    /// @return price ETH price in USD, 8 decimals (Chainlink standard)
    /// @return updatedAt timestamp of last update
    function getETHUSDPrice() external view returns (uint256 price, uint256 updatedAt);
}
