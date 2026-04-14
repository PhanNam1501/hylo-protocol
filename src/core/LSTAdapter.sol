// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/ILSTOracle.sol";

/// @dev Minimal interface for stETH (Lido)
interface IStETH {
    /// @notice Returns ETH backing for a share amount.
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

/// @dev Minimal interface for rETH (Rocket Pool)
interface IRocketETH {
    /// @notice Returns current rETH exchange rate.
    function getExchangeRate() external view returns (uint256);
}

/// @dev Minimal interface for wstETH (wrapped stETH — non-rebasing)
interface IWstETH {
    /// @notice Returns ETH-equivalent amount for wstETH.
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
}

/// @title LSTAdapter
/// @notice Returns on-chain ETH rates for supported LST assets.
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
    /// @notice Returns ETH per 1 LST token in WAD.
    function getLSTRate(address lst) external view override returns (uint256 rate) {
        if (lst == stETH) {
            rate = IStETH(stETH).getPooledEthByShares(1e18);
        } else if (lst == rETH) {
            rate = IRocketETH(rETH).getExchangeRate();
        } else if (lst == wstETH) {
            rate = IWstETH(wstETH).getStETHByWstETH(1e18);
        } else {
            revert("LSTAdapter: unsupported LST");
        }
    }
}
