//spdx-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StdStorage, stdStorage} from "forge-std/Test.sol";

import {CurvanceTokenRateProvider} from "../../src/lst/providers/CurvanceTokenRateProvider.sol";

contract BloomTest is Test {
    address constant C_WMON = 0x0fcEd51b526BfA5619F83d97b54a57e3327eB183;

    CurvanceTokenRateProvider public cMonRateProvider;

    function setUp() public {
        uint256 fork = vm.createFork(vm.envString("MONAD_RPC"), 69_500_000);
        vm.selectFork(fork);

        cMonRateProvider = new CurvanceTokenRateProvider(C_WMON);
    }

    function test_getRate_shouldSuccess() public {
        // bloom.createMarketData(WMON, address(pythOracle));
        uint256 rate = cMonRateProvider.getRate();
        assertApproxEqAbs(rate, 1.5 * 1e18, 1.5 * 1e18);
    }
}
