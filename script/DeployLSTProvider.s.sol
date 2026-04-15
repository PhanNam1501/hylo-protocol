// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/lst/LSTRateProviderFactory.sol";
import "../src/lst/LSTAdapter.sol";
import "../src/lst/providers/StETHRateProvider.sol";
import "../src/lst/providers/RETHRateProvider.sol";
import "../src/lst/providers/WstETHRateProvider.sol";

/// @notice Deploy a deterministic LST provider via CREATE2 and register it in LSTAdapter.
contract DeployLSTProvider is Script {
    /// @dev 1=StETHRateProvider, 2=RETHRateProvider, 3=WstETHRateProvider.
    function run() external {
        address factoryAddr = vm.envAddress("LST_PROVIDER_FACTORY");
        address adapterAddr = vm.envAddress("LST_ADAPTER");
        address lstToken = vm.envAddress("LST_TOKEN");
        uint256 providerKind = vm.envUint("PROVIDER_KIND");
        bytes32 extraSalt = vm.envOr("EXTRA_SALT", bytes32(0));
        bool shouldRegister = vm.envOr("REGISTER_IN_ADAPTER", true);

        bytes memory creationCode = _creationCode(providerKind);
        bytes memory constructorArgs = abi.encode(lstToken);

        LSTRateProviderFactory factory = LSTRateProviderFactory(factoryAddr);
        bytes32 salt = factory.computeSalt(lstToken, extraSalt);
        bytes32 initCodeHash = factory.computeInitCodeHash(creationCode, constructorArgs);
        address predicted = factory.predictProvider(salt, initCodeHash);

        vm.startBroadcast();

        address provider = factory.deployProvider(salt, creationCode, constructorArgs);
        require(provider == predicted, "DeployLSTProvider: predicted mismatch");

        if (shouldRegister) {
            LSTAdapter(adapterAddr).setLSTRateProvider(lstToken, provider);
        }

        vm.stopBroadcast();

        console2.log("salt:");
        console2.logBytes32(salt);
        console2.log("initCodeHash:");
        console2.logBytes32(initCodeHash);
        console2.log("predicted provider:", predicted);
        console2.log("deployed provider:", provider);
    }

    function _creationCode(uint256 providerKind) internal pure returns (bytes memory code) {
        if (providerKind == 1) return type(StETHRateProvider).creationCode;
        if (providerKind == 2) return type(RETHRateProvider).creationCode;
        if (providerKind == 3) return type(WstETHRateProvider).creationCode;
        revert("DeployLSTProvider: invalid PROVIDER_KIND");
    }
}
