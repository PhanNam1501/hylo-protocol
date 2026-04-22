// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ImmutableClone} from "../libraries/ImmutableClone.sol";
import {IBloomVault} from "../interfaces/core/IBloomVault.sol";
import {IBloomVaultFactory} from "../interfaces/core/IBloomVaultFactory.sol";

/// @title BloomVaultFactory
contract BloomVaultFactory is Ownable2Step, AccessControl, IBloomVaultFactory {
    bytes32 public constant VAULT_CREATOR_ROLE = keccak256("VAULT_CREATOR_ROLE");

    address private _vaultImplementation;
    mapping(address => mapping(address => address)) private _vaultByPair;
    address private _lstOracle;
    address private _priceOracle;
    address private _feeController;
    address private _stabilityPool;
    address private _feeRecipient;

    constructor(address initialOwner, address initialFeeRecipient) Ownable(initialOwner) {
        _setFeeRecipient(initialFeeRecipient);
    }

    function owner() public view override(IBloomVaultFactory, Ownable) returns (address) {
        return super.owner();
    }

    function getVault(address bloomUSD, address xNative) external view override returns (address vault) {
        return _vaultByPair[bloomUSD][xNative];
    }

    function getVaultImplementation() external view override returns (address implementation) {
        return _vaultImplementation;
    }
    
    function getFeeRecipient() external view override returns (address feeRecipient) {
        return _feeRecipient;
    }

    function setVaultImplementation(address newImplementation) external override onlyOwner {
        if (newImplementation == address(0)) revert BloomVaultFactory__ZeroImplementation();
        address oldImplementation = _vaultImplementation;
        if (oldImplementation == newImplementation) revert BloomVaultFactory__SameImplementation();

        _vaultImplementation = newImplementation;
        emit VaultImplementationSet(oldImplementation, newImplementation);
    }
    
    function setFeeRecipient(address feeRecipient) external override onlyOwner {
        _setFeeRecipient(feeRecipient);
    }

    function setVaultDependencies(address lstOracle, address priceOracle, address feeController, address stabilityPool)
        external
        override
        onlyOwner
    {
        _setVaultDependencies(lstOracle, priceOracle, feeController, stabilityPool);
    }

    
    function createVault(address bloomUSD, address xNative) external override onlyOwner returns (address vault) {
        _checkDependenciesSet();
        bytes32 salt = _computeVaultSalt(bloomUSD, xNative);
        bytes memory data = _getVaultImmutableData(bloomUSD, xNative);

        vault = ImmutableClone.cloneDeterministic(_vaultImplementation, data, salt);
        IBloomVault(vault).initialize();
        _vaultByPair[bloomUSD][xNative] = vault;

        emit VaultDeployed(salt, ImmutableClone.initCodeHash(_vaultImplementation, data), vault);
    }

    function _setVaultDependencies(address lstOracle, address priceOracle, address feeController, address stabilityPool)
        internal
    {
        if (lstOracle == address(0)) revert BloomVaultFactory__ZeroLSTOracle();
        if (priceOracle == address(0)) revert BloomVaultFactory__ZeroPriceOracle();
        if (feeController == address(0)) revert BloomVaultFactory__ZeroFeeController();
        if (stabilityPool == address(0)) revert BloomVaultFactory__ZeroStabilityPool();

        _lstOracle = lstOracle;
        _priceOracle = priceOracle;
        _feeController = feeController;
        _stabilityPool = stabilityPool;

        emit VaultDependenciesSet(lstOracle, priceOracle, feeController, stabilityPool);
    }
    
    function _setFeeRecipient(address feeRecipient) internal {
        if (feeRecipient == address(0)) revert BloomVaultFactory__ZeroFeeRecipient();
        address oldFeeRecipient = _feeRecipient;
        _feeRecipient = feeRecipient;
        emit FeeRecipientSet(oldFeeRecipient, feeRecipient);
    }

    function _checkDependenciesSet() internal view {
        if (_lstOracle == address(0)) revert BloomVaultFactory__DependenciesNotSet();
    }

    function _computeVaultSalt(address bloomUSD, address xNative) internal view returns (bytes32) {
        return keccak256(abi.encode(bloomUSD, xNative, _lstOracle, _priceOracle, _feeController, _stabilityPool));
    }

    function _getVaultImmutableData(address bloomUSD, address xNative) internal view returns (bytes memory) {
        return abi.encodePacked(bloomUSD, xNative, _lstOracle, _priceOracle, _feeController, _stabilityPool, _feeRecipient);
    }

    function hasRole(bytes32 role, address account) public view override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE) return account == owner();
        return super.hasRole(role, account);
    }

    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE) revert();
        return super._grantRole(role, account);
    }
}
