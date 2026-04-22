// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBloomVaultFactory {
    error BloomVaultFactory__ZeroLSTOracle();
    error BloomVaultFactory__ZeroPriceOracle();
    error BloomVaultFactory__ZeroFeeController();
    error BloomVaultFactory__ZeroStabilityPool();
    error BloomVaultFactory__DependenciesNotSet();
    error BloomVaultFactory__ZeroImplementation();
    error BloomVaultFactory__SameImplementation();
    error BloomVaultFactory__ZeroFeeRecipient();

    event VaultDeployed(bytes32 indexed salt, bytes32 indexed initCodeHash, address indexed vault);
    event VaultDependenciesSet(
        address indexed lstOracle,
        address indexed priceOracle,
        address indexed feeController,
        address stabilityPool
    );
    event VaultImplementationSet(address indexed oldImplementation, address indexed newImplementation);
    event FeeRecipientSet(address indexed oldFeeRecipient, address indexed newFeeRecipient);
    
    function owner() external view returns (address);

    function getVault(address bloomUSD, address xNative) external view returns (address vault);

    function getVaultImplementation() external view returns (address implementation);
    
    function getFeeRecipient() external view returns (address feeRecipient);

    function setVaultImplementation(address newImplementation) external;
    
    function setFeeRecipient(address feeRecipient) external;

    function setVaultDependencies(address lstOracle, address priceOracle, address feeController, address stabilityPool)
        external;

    function createVault(address bloomUSD, address xNative) external returns (address vault);
}
