// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/ILSTOracle.sol";

/// @dev Minimal interface for stETH (Lido)
interface IStETH {
    /// @notice stETH uses a share-based rebasing model
    ///         getPooledEthByShares gives ETH backing per share
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

/// @dev Minimal interface for rETH (Rocket Pool)
interface IRocketETH {
    /// @notice rETH directly exposes exchange rate
    function getExchangeRate() external view returns (uint256);
}

/// @dev Minimal interface for wstETH (wrapped stETH — non-rebasing)
interface IWstETH {
    /// @notice Returns the amount of ETH that corresponds to `_wstETHAmount` wstETH
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
}

/// @title LSTAdapter
/// @notice Implements True LST Pricing for EVM LSTs (stETH, rETH, wstETH).
///
///         Mirrors Hylo's oracle-manipulation-resistant design:
///           True LST Price (ETH) = ETH staked in pool / LST supply
///
///         On EVM:
///           - stETH:  getPooledEthByShares(1e18) → ETH per share
///           - rETH:   getExchangeRate()           → ETH per rETH  
///           - wstETH: getStETHByWstETH(1e18)      → stETH per wstETH (≈ ETH)
///
///         All rates are sourced directly from the LST contracts — no external oracle.
///         Only ETH/USD still needs Chainlink (1 oracle total, same as Hylo).
contract LSTAdapter is ILSTOracle {
    address public immutable stETH;
    address public immutable rETH;
    address public immutable wstETH;

    constructor(address _stETH, address _rETH, address _wstETH) {
        stETH  = _stETH;
        rETH   = _rETH;
        wstETH = _wstETH;
    }

    /// @inheritdoc ILSTOracle
    /// @notice Returns WAD-scaled ETH per 1 LST token
    function getLSTRate(address lst) external view override returns (uint256 rate) {
        if (lst == stETH) {
            // stETH: 1 share = getPooledEthByShares(1e18) wei of ETH
            rate = IStETH(stETH).getPooledEthByShares(1e18);
        } else if (lst == rETH) {
            // rETH: direct exchange rate, already WAD
            rate = IRocketETH(rETH).getExchangeRate();
        } else if (lst == wstETH) {
            // wstETH: stETH per wstETH ≈ ETH per wstETH (stETH is 1:1 with ETH net of slashing)
            rate = IWstETH(wstETH).getStETHByWstETH(1e18);
        } else {
            revert("LSTAdapter: unsupported LST");
        }
    }
}
