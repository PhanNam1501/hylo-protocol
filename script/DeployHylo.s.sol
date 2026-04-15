// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/core/HyloVault.sol";
import "../src/core/FeeController.sol";
import "../src/stability/StabilityPool.sol";
import "../src/tokens/HyUSD.sol";
import "../src/tokens/XETH.sol";
import "../src/tokens/ShyUSD.sol";
import "../src/lst/LSTAdapter.sol";
import "../src/core/ChainlinkPriceOracle.sol";

contract DeployHylo is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address treasury = vm.envAddress("TREASURY");
        address ethUsdFeed = vm.envAddress("ETH_USD_FEED");

        vm.startBroadcast();

        (HyUSD hyUSD, XETH xETH, ShyUSD shyUSD) = _deployTokens(admin);
        (FeeController feeController, StabilityPool stabilityPool) = _deployCore(
            admin,
            hyUSD,
            xETH,
            shyUSD
        );
        LSTAdapter lstOracle = new LSTAdapter(admin);
        IPriceOracle priceOracle = new ChainlinkPriceOracle(ethUsdFeed);
        HyloVault vault = _deployVault(
            hyUSD,
            xETH,
            lstOracle,
            priceOracle,
            feeController,
            stabilityPool,
            treasury,
            admin
        );
        _wireRoles(hyUSD, xETH, shyUSD, stabilityPool, vault);

        // LST provider registration flow:
        // 1) deploy provider(s) via LSTRateProviderFactory
        // 2) call lstOracle.setLSTRateProvider(lstToken, provider)
        // 3) call vault.addLST(lstToken)

        vm.stopBroadcast();
    }

    function _deployTokens(
        address admin
    ) internal returns (HyUSD hyUSD, XETH xETH, ShyUSD shyUSD) {
        hyUSD = new HyUSD(admin);
        xETH = new XETH(admin);
        shyUSD = new ShyUSD(admin);
    }

    function _deployCore(
        address admin,
        HyUSD hyUSD,
        XETH xETH,
        ShyUSD shyUSD
    ) internal returns (FeeController feeController, StabilityPool stabilityPool) {
        feeController = new FeeController(admin);
        stabilityPool = new StabilityPool(
            address(hyUSD),
            address(xETH),
            address(shyUSD),
            admin
        );
    }

    function _deployVault(
        HyUSD hyUSD,
        XETH xETH,
        LSTAdapter lstOracle,
        IPriceOracle priceOracle,
        FeeController feeController,
        StabilityPool stabilityPool,
        address treasury,
        address admin
    ) internal returns (HyloVault vault) {
        vault = new HyloVault(
            address(hyUSD),
            address(xETH),
            address(ILSTOracle(address(lstOracle))),
            address(priceOracle),
            address(feeController),
            address(stabilityPool),
            treasury,
            admin
        );
    }

    function _wireRoles(
        HyUSD hyUSD,
        XETH xETH,
        ShyUSD shyUSD,
        StabilityPool stabilityPool,
        HyloVault vault
    ) internal {
        hyUSD.grantRole(hyUSD.MINTER_ROLE(), address(vault));
        xETH.grantRole(xETH.MINTER_ROLE(), address(vault));
        stabilityPool.grantRole(stabilityPool.VAULT_ROLE(), address(vault));
        shyUSD.grantRole(shyUSD.MINTER_ROLE(), address(stabilityPool));
    }
}

