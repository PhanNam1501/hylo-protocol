// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../interfaces/lst/ILSTRateProvider.sol";

/// @title LSTRateProviderBase
/// @notice Abstract base contract for LST-specific ETH rate providers.
abstract contract LSTRateProviderBase is ILSTRateProvider {
    address public immutable override lstToken;

    constructor(address _lstToken) {
        require(_lstToken != address(0), "LSTRateProvider: zero token");
        lstToken = _lstToken;
    }
}
