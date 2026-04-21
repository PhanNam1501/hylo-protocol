// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../base/LSTRateProviderBase.sol";

interface ICuvanceToken {
    function exchangeRate() external view returns (uint256);
}

/// @notice Provider for rETH using Rocket Pool exchange rate.
contract CurvanceTokenRateProvider is LSTRateProviderBase {
    constructor(address _lstToken) LSTRateProviderBase(_lstToken) {}

    function getRate() external view override returns (uint256 rate) {
        rate = ICuvanceToken(lstToken).exchangeRate();
    }
}
