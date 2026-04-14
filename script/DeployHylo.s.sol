// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/core/HyloVault.sol";
import "../src/core/FeeController.sol";
import "../src/stability/StabilityPool.sol";
import "../src/tokens/HyUSD.sol";
import "../src/tokens/XETH.sol";
import "../src/tokens/ShyUSD.sol";
import "../src/core/LSTAdapter.sol";
import "../src/core/ChainlinkPriceOracle.sol";

contract DeployHylo is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address treasury = vm.envAddress("TREASURY");

        // LST addresses (optional, depending on network)
        address stETH = vm.envOr("STETH", address(0));
        address rETH = vm.envOr("RETH", address(0));
        address wstETH = vm.envOr("WSTETH", address(0));

        // Chainlink ETH/USD feed address
        address ethUsdFeed = vm.envAddress("ETH_USD_FEED");

        vm.startBroadcast();

        HyUSD hyUSD = new HyUSD(admin);
        XETH xETH = new XETH(admin);
        ShyUSD shyUSD = new ShyUSD(admin);

        FeeController feeController = new FeeController(admin);
        StabilityPool stabilityPool = new StabilityPool(
            address(hyUSD),
            address(xETH),
            address(shyUSD),
            admin
        );

        ILSTOracle lstOracle = new LSTAdapter(stETH, rETH, wstETH);
        IPriceOracle priceOracle = new ChainlinkPriceOracle(ethUsdFeed);

        HyloVault vault = new HyloVault(
            address(hyUSD),
            address(xETH),
            address(lstOracle),
            address(priceOracle),
            address(feeController),
            address(stabilityPool),
            treasury,
            admin
        );

        // Wire roles
        hyUSD.grantRole(hyUSD.MINTER_ROLE(), address(vault));
        xETH.grantRole(xETH.MINTER_ROLE(), address(vault));
        stabilityPool.grantRole(stabilityPool.VAULT_ROLE(), address(vault));
        shyUSD.grantRole(shyUSD.MINTER_ROLE(), address(stabilityPool));

        // Add LSTs to basket if provided
        if (stETH != address(0)) vault.addLST(stETH);
        if (rETH != address(0)) vault.addLST(rETH);
        if (wstETH != address(0)) vault.addLST(wstETH);

        vm.stopBroadcast();
    }
}

