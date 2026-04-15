// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../src/lst/LSTRateProviderFactory.sol";
import "../../src/lst/base/LSTRateProviderBase.sol";

contract FactoryMockProvider is LSTRateProviderBase {
    uint256 internal _rate;

    constructor(address _lstToken, uint256 initialRate) LSTRateProviderBase(_lstToken) {
        _rate = initialRate;
    }

    function getRate() external view override returns (uint256 rate) {
        return _rate;
    }
}

contract LSTRateProviderFactoryTest is Test {
    address internal owner = address(0xCAFE);
    address internal user = address(0xBEEF);
    address internal lst = address(0x1111);

    LSTRateProviderFactory internal factory;

    function setUp() external {
        factory = new LSTRateProviderFactory(owner);
    }

    function test_predictMatchesDeployedAddress() external {
        bytes memory creationCode = type(FactoryMockProvider).creationCode;
        bytes memory constructorArgs = abi.encode(lst, 1.01e18);
        bytes32 salt = keccak256(abi.encode(lst, bytes32("salt-1")));

        bytes32 initCodeHash = factory.computeInitCodeHash(creationCode, constructorArgs);
        address predicted = factory.predictProvider(salt, initCodeHash);

        vm.prank(owner);
        address deployed = factory.deployProvider(salt, creationCode, constructorArgs);

        assertEq(deployed, predicted);
        assertEq(FactoryMockProvider(deployed).lstToken(), lst);
        assertEq(FactoryMockProvider(deployed).getRate(), 1.01e18);
    }

    function test_revertWhenNonOwnerDeploys() external {
        bytes memory creationCode = type(FactoryMockProvider).creationCode;
        bytes memory constructorArgs = abi.encode(lst, 1e18);
        bytes32 salt = keccak256(abi.encode(lst, bytes32("salt-2")));

        vm.prank(user);
        vm.expectRevert();
        factory.deployProvider(salt, creationCode, constructorArgs);
    }

    function test_revertWhenDeployingSameSaltAndBytecodeTwice() external {
        bytes memory creationCode = type(FactoryMockProvider).creationCode;
        bytes memory constructorArgs = abi.encode(lst, 1e18);
        bytes32 salt = keccak256(abi.encode(lst, bytes32("same-salt")));

        vm.startPrank(owner);
        factory.deployProvider(salt, creationCode, constructorArgs);

        vm.expectRevert("Factory: CREATE2 failed");
        factory.deployProvider(salt, creationCode, constructorArgs);
        vm.stopPrank();
    }
}
