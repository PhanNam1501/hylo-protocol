// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/lst/ILSTOracle.sol";
import "../interfaces/lst/ILSTRateProvider.sol";

/// @title LSTAdapter
/// @notice Registry adapter mapping each LST token to a rate provider contract.
contract LSTAdapter is ILSTOracle, Ownable {
    mapping(address => address) public lstRateProvider;

    event LSTRateProviderUpdated(address indexed lstToken, address indexed provider);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Sets/updates the provider contract for an LST token.
    /// @dev Set `provider` to zero address to remove support.
    function setLSTRateProvider(address lstToken, address provider) external onlyOwner {
        require(lstToken != address(0), "LSTAdapter: zero token");
        if (provider != address(0)) {
            require(
                ILSTRateProvider(provider).lstToken() == lstToken,
                "LSTAdapter: provider-token mismatch"
            );
        }
        lstRateProvider[lstToken] = provider;
        emit LSTRateProviderUpdated(lstToken, provider);
    }

    /// @inheritdoc ILSTOracle
    /// @notice Returns ETH per 1 LST token in WAD.
    function getLSTRate(address lst) external view override returns (uint256 rate) {
        address provider = lstRateProvider[lst];
        require(provider != address(0), "LSTAdapter: unsupported LST");
        rate = ILSTRateProvider(provider).getRate();
        require(rate > 0, "LSTAdapter: invalid rate");
    }
}
