// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title XETH
/// @notice Leveraged long ETH token. Holds the Variable Reserve — everything
///         in the collateral pool after backing hyUSD 1:1.
///
///         xETH Price = Variable Reserve / xETH Supply
///         Effective Leverage = Total ETH / Variable Reserve
///
///         xETH is the "residual claimant":
///           - ETH pumps → xETH earns leveraged upside
///           - ETH dumps → xETH absorbs the loss (protecting hyUSD peg)
contract XETH is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20("Hylo xETH", "xETH") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
}
