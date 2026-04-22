// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/core/BloomVault.sol";
import "../src/core/BloomVaultFactory.sol";
import "../src/core/FeeController.sol";
import "../src/stability/StabilityPool.sol";
import "../src/tokens/HyUSD.sol";
import "../src/tokens/XETH.sol";
import "../src/tokens/ShyUSD.sol";
import "../src/lst/LSTAdapter.sol";
import "../src/core/ChainlinkPriceOracle.sol";

contract DeployBloom is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address treasury = vm.envAddress("TREASURY");
        address nativeUsdFeed = vm.envAddress("NATIVE_USD_FEED");
        address permit2 = vm.envAddress("PERMIT2");

        vm.startBroadcast();

        (BloomUSD bloomUSD, XNative xNative, SBloomUSD sbloomUSD) = _deployTokens(admin);
        (FeeController feeController, StabilityPool stabilityPool) =
            _deployCore(admin, bloomUSD, xNative, sbloomUSD, permit2);
        LSTAdapter lstOracle = new LSTAdapter(admin);
        IPriceOracle priceOracle = new ChainlinkPriceOracle(nativeUsdFeed);
        (, BloomVault vault) =
            _deployVault(admin, bloomUSD, xNative, lstOracle, priceOracle, feeController, stabilityPool, treasury);
        _wireRoles(bloomUSD, xNative, sbloomUSD, stabilityPool, vault);

        // LST provider registration flow:
        // 1) deploy provider(s) via LSTRateProviderFactory
        // 2) call lstOracle.setLSTRateProvider(lstToken, provider)
        // 3) call vault.addLST(lstToken)

        vm.stopBroadcast();
    }

    function _deployTokens(address admin) internal returns (BloomUSD bloomUSD, XNative xNative, SBloomUSD sbloomUSD) {
        bloomUSD = new BloomUSD(admin);
        xNative = new XNative(admin);
        sbloomUSD = new SBloomUSD(admin);
    }

    function _deployCore(address admin, BloomUSD bloomUSD, XNative xNative, SBloomUSD sbloomUSD, address _permit2)
        internal
        returns (FeeController feeController, StabilityPool stabilityPool)
    {
        feeController = new FeeController(admin);
        stabilityPool = new StabilityPool(address(bloomUSD), address(xNative), address(sbloomUSD), admin, _permit2);
    }

    function _deployVault(
        address factoryOwner,
        BloomUSD bloomUSD,
        XNative xNative,
        LSTAdapter lstOracle,
        IPriceOracle priceOracle,
        FeeController feeController,
        StabilityPool stabilityPool,
        address treasury
    ) internal returns (BloomVaultFactory factory, BloomVault vault) {
        factory = new BloomVaultFactory(factoryOwner, treasury);
        BloomVault implementation = new BloomVault(IBloomVaultFactory(address(factory)));

        factory.setVaultImplementation(address(implementation));
        factory.setVaultDependencies(address(lstOracle), address(priceOracle), address(feeController), address(stabilityPool));

        address vaultAddr = factory.createVault(address(bloomUSD), address(xNative));
        vault = BloomVault(vaultAddr);
    }

    function _wireRoles(
        BloomUSD bloomUSD,
        XNative xNative,
        SBloomUSD sbloomUSD,
        StabilityPool stabilityPool,
        BloomVault vault
    ) internal {
        bloomUSD.grantRole(bloomUSD.MINTER_ROLE(), address(vault));
        xNative.grantRole(xNative.MINTER_ROLE(), address(vault));
        stabilityPool.grantRole(stabilityPool.VAULT_ROLE(), address(vault));
        sbloomUSD.grantRole(sbloomUSD.MINTER_ROLE(), address(stabilityPool));
    }
}
