// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../base/LSTRateProviderBase.sol";

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @notice Provider for rETH using Rocket Pool exchange rate.
contract ERC4626RateProvider is LSTRateProviderBase {
    constructor(address _lstToken) LSTRateProviderBase(_lstToken) {}

    function getRate() external view override returns (uint256 rate) {
        rate =
            (ERC4626(lstToken).totalAssets() * 1e18) /
            ERC4626(lstToken).totalSupply();
    }
}
