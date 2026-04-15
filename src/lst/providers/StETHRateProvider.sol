// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../base/LSTRateProviderBase.sol";

interface IStETH {
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

/// @notice Provider for stETH using Lido's on-chain share conversion.
contract StETHRateProvider is LSTRateProviderBase {
    constructor(address _lstToken) LSTRateProviderBase(_lstToken) {}

    function getRate() external view override returns (uint256 rate) {
        rate = IStETH(lstToken).getPooledEthByShares(1e18);
    }
}
