//spdx-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StdStorage, stdStorage} from "forge-std/Test.sol";

import {ERC4626RateProvider} from "../../src/lst/providers/ERC4626RateProvider.sol";

contract BloomTest is Test {
    address constant SH_MON = 0x1B68626dCa36c7fE922fD2d55E4f631d962dE19c;

    ERC4626RateProvider public shMonRateProvider;

    function setUp() public {
        uint256 fork = vm.createFork(vm.envString("MONAD_RPC"), 69_500_000);
        vm.selectFork(fork);

        shMonRateProvider = new ERC4626RateProvider(SH_MON);
    }

    function test_getRate_shouldSuccess() public {
        // bloom.createMarketData(WMON, address(pythOracle));
        uint256 rate = shMonRateProvider.getRate();
        assertApproxEqAbs(rate, 1.5 * 1e18, 1.5 * 1e18);
    }
}
