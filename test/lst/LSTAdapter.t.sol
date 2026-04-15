// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../src/lst/LSTAdapter.sol";
import "../../src/lst/base/LSTRateProviderBase.sol";

contract MockLSTRateProvider is LSTRateProviderBase {
    uint256 internal _rate;

    constructor(address _lstToken, uint256 initialRate) LSTRateProviderBase(_lstToken) {
        _rate = initialRate;
    }

    function setRate(uint256 newRate) external {
        _rate = newRate;
    }

    function getRate() external view override returns (uint256 rate) {
        return _rate;
    }
}

contract LSTAdapterTest is Test {
    address internal owner = address(0xABCD);
    address internal user = address(0xBEEF);
    address internal lst = address(0x1111);
    address internal otherLst = address(0x2222);

    LSTAdapter internal adapter;
    MockLSTRateProvider internal provider;
    MockLSTRateProvider internal wrongProvider;

    function setUp() external {
        adapter = new LSTAdapter(owner);
        provider = new MockLSTRateProvider(lst, 1.02e18);
        wrongProvider = new MockLSTRateProvider(otherLst, 1.05e18);
    }

    function test_setAndGetLSTRate() external {
        vm.prank(owner);
        adapter.setLSTRateProvider(lst, address(provider));

        uint256 rate = adapter.getLSTRate(lst);
        assertEq(rate, 1.02e18);
    }

    function test_revertWhenUnsupportedLST() external {
        vm.expectRevert("LSTAdapter: unsupported LST");
        adapter.getLSTRate(lst);
    }

    function test_revertWhenProviderTokenMismatch() external {
        vm.prank(owner);
        vm.expectRevert("LSTAdapter: provider-token mismatch");
        adapter.setLSTRateProvider(lst, address(wrongProvider));
    }

    function test_revertWhenNonOwnerSetsProvider() external {
        vm.prank(user);
        vm.expectRevert();
        adapter.setLSTRateProvider(lst, address(provider));
    }

    function test_removeProviderBySettingZero() external {
        vm.startPrank(owner);
        adapter.setLSTRateProvider(lst, address(provider));
        adapter.setLSTRateProvider(lst, address(0));
        vm.stopPrank();

        vm.expectRevert("LSTAdapter: unsupported LST");
        adapter.getLSTRate(lst);
    }
}
