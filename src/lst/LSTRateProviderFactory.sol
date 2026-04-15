// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title LSTRateProviderFactory
/// @notice Deploys any LST rate provider with CREATE2 and predicts deterministic addresses.
contract LSTRateProviderFactory is Ownable {
    event ProviderDeployed(
        bytes32 indexed salt,
        bytes32 indexed initCodeHash,
        address indexed provider,
        bytes32 bytecodeHash
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Deploys any provider contract bytecode + constructor args via CREATE2.
    /// @param salt CREATE2 salt.
    /// @param creationCode Contract creation code (type(MyProvider).creationCode).
    /// @param constructorArgs ABI-encoded constructor args.
    function deployProvider(
        bytes32 salt,
        bytes calldata creationCode,
        bytes calldata constructorArgs
    ) external onlyOwner returns (address provider) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(bytecode);
        bytes32 codeHash = keccak256(creationCode);

        assembly {
            provider := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(provider != address(0), "Factory: CREATE2 failed");
        emit ProviderDeployed(salt, initCodeHash, provider, codeHash);
    }

    /// @notice Predicts address for any CREATE2 deployment from this factory.
    function predictProvider(bytes32 salt, bytes32 initCodeHash) external view returns (address) {
        return _predictAddress(salt, initCodeHash);
    }

    /// @notice Computes init code hash from creation code and constructor args.
    function computeInitCodeHash(
        bytes calldata creationCode,
        bytes calldata constructorArgs
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(creationCode, constructorArgs));
    }

    function computeSalt(address lstToken, bytes32 extraSalt) external pure returns (bytes32) {
        return keccak256(abi.encode(lstToken, extraSalt));
    }

    function _predictAddress(bytes32 salt, bytes32 initCodeHash) internal view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                initCodeHash
            )
        );
        return address(uint160(uint256(hash)));
    }
}
