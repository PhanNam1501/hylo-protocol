// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/tokens/IHyUSD.sol";

/// @title BloomUSD
/// @notice Protocol stablecoin token with restricted mint and burn.
contract BloomUSD is ERC20, AccessControl, IBloomUSD {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20("Bloom USD", "bloomUSD") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }

    function totalSupply() public view override(ERC20, IBloomUSD) returns (uint256) {
        return super.totalSupply();
    }
}
