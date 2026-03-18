// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ShyUSD
/// @notice Share token representing a proportional claim on the Stability Pool.
///         NOT a fixed 1:1 token — share price increases as yield is harvested.
///
///         Share Price = Pool hyUSD balance / Total shyUSD supply
///
///         Yield mechanism (auto-compound):
///           1. LST staking rewards accrue → TVL increases
///           2. Protocol mints new hyUSD (backed by excess collateral)
///           3. Injects into Stability Pool → share price rises
///           4. Holders never need to claim — just hold shyUSD
///
///         Drawdown mechanism (CR < 130%):
///           Protocol burns pool's hyUSD, mints xETH into pool instead.
///           Holders now hold shyUSD backed by mix of hyUSD + xETH.
contract ShyUSD is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20("Staked hyUSD", "shyUSD") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
}
