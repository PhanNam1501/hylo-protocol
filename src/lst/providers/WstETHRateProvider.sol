// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../base/LSTRateProviderBase.sol";

interface IWstETH {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
}

/// @notice Provider for wstETH using wrapped->stETH conversion.
contract WstETHRateProvider is LSTRateProviderBase {
    constructor(address _lstToken) LSTRateProviderBase(_lstToken) {}

    function getRate() external view override returns (uint256 rate) {
        rate = IWstETH(lstToken).getStETHByWstETH(1e18);
    }
}
