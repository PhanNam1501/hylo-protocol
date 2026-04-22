// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/tokens/IXETH.sol";

/// @title XNative
/// @notice Protocol xNative token with restricted mint and burn.
contract XNative is ERC20, AccessControl, IXNative {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20("Bloom xNative", "xNative") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }

    function totalSupply() public view override(ERC20, IXNative) returns (uint256) {
        return super.totalSupply();
    }
}
