// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../tokens/ShyUSD.sol";
import "../tokens/XETH.sol";
import "../libraries/HyloMath.sol";

/// @title StabilityPool
/// @notice Implements Hylo's Stability Pool — staked hyUSD that:
///
///   1. YIELD (auto-compound):
///      LST staking rewards → protocol harvests excess collateral →
///      mints new hyUSD → injects here → share price rises.
///      Holders earn yield by holding shyUSD (no manual claiming).
///
///   2. DRAWDOWN (CR < 130% — Mode 2):
///      Protocol burns pool's hyUSD supply → mints xETH into pool.
///      This reduces hyUSD supply → CR rises (non-linear effect).
///      Holders now hold a mix of hyUSD + xETH in their shares.
///      If ETH recovers, the xETH portion profits.
///
///   Share Model:
///     Share Price = (pool hyUSD + pool xETH worth) / shyUSD supply
///     When yield injected: share price rises (more hyUSD per share)
///     When drawdown: hyUSD replaced by xETH (risk, but also upside)
///
///   Share accounting uses RAY (1e27) for precision.
contract StabilityPool is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using HyloMath for uint256;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    // ─── Tokens ───────────────────────────────────────────────────────────
    IERC20 public immutable hyUSD;
    XETH public immutable xETH;
    ShyUSD public immutable shyUSD;

    // ─── Pool State ───────────────────────────────────────────────────────
    // hyUSD sitting in pool (increases on deposit + yield injection, decreases on withdraw + drawdown)
    uint256 public hyUSDBalance;
    // xETH accumulated in pool from drawdowns
    uint256 public xETHBalance;

    // Total shyUSD shares in existence (tracked separately for precision)
    // Note: shyUSD.totalSupply() == totalShares always
    // We use RAY-scaled internal share price

    // ─── Events ───────────────────────────────────────────────────────────
    event Deposited(
        address indexed user,
        uint256 hyUSDAmount,
        uint256 sharesIssued
    );
    event Withdrawn(
        address indexed user,
        uint256 shares,
        uint256 hyUSDOut,
        uint256 xETHOut
    );
    event YieldInjected(uint256 hyUSDAmount, uint256 newSharePrice);
    event DrawdownExecuted(
        uint256 hyUSDBurned,
        uint256 xETHMinted,
        uint256 newCR
    );

    constructor(
        address _hyUSD,
        address _xETH,
        address _shyUSD,
        address _admin
    ) {
        hyUSD = IERC20(_hyUSD);
        xETH = XETH(_xETH);
        shyUSD = ShyUSD(_shyUSD);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // ─── Share Price ──────────────────────────────────────────────────────

    /// @notice Returns current share price in RAY (1 RAY = 1 hyUSD per share at genesis)
    ///         Share price only counts hyUSD — xETH portion tracked separately
    ///         and returned proportionally on withdrawal.
    function sharePrice() public view returns (uint256) {
        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) return HyloMath.RAY; // Genesis: 1:1
        return HyloMath.rayDiv((hyUSDBalance * HyloMath.RAY) / 1, supply);
    }

    // ─── Deposit ──────────────────────────────────────────────────────────

    /// @notice Deposit hyUSD → receive shyUSD shares
    /// @param amount Amount of hyUSD to deposit (WAD)
    function deposit(
        uint256 amount
    ) external nonReentrant returns (uint256 shares) {
        require(amount > 0, "SP: zero amount");

        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) {
            shares = amount; // Bootstrap: 1 share per hyUSD
        } else {
            // shares = amount * totalShares / hyUSDBalance
            shares = (amount * supply) / hyUSDBalance;
        }
        require(shares > 0, "SP: zero shares");

        hyUSD.safeTransferFrom(msg.sender, address(this), amount);
        hyUSDBalance += amount;
        shyUSD.mint(msg.sender, shares);

        emit Deposited(msg.sender, amount, shares);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────

    /// @notice Burn shyUSD shares → receive pro-rata hyUSD + xETH
    /// @param shares Amount of shyUSD to burn
    function withdraw(
        uint256 shares
    ) external nonReentrant returns (uint256 hyUSDOut, uint256 xETHOut) {
        require(shares > 0, "SP: zero shares");
        uint256 supply = shyUSD.totalSupply();
        require(shares <= supply, "SP: exceeds supply");

        // Pro-rata claim on both assets
        hyUSDOut = (hyUSDBalance * shares) / supply;
        xETHOut = (xETHBalance * shares) / supply;

        shyUSD.burn(msg.sender, shares);
        hyUSDBalance -= hyUSDOut;
        if (xETHOut > 0) xETHBalance -= xETHOut;

        if (hyUSDOut > 0) hyUSD.safeTransfer(msg.sender, hyUSDOut);
        if (xETHOut > 0)
            IERC20(address(xETH)).safeTransfer(msg.sender, xETHOut);

        emit Withdrawn(msg.sender, shares, hyUSDOut, xETHOut);
    }

    // ─── Yield Injection (called by HyloVault on harvest) ─────────────────

    /// @notice Vault injects harvested LST yield as new hyUSD.
    ///         Increases hyUSDBalance without minting new shares → share price rises.
    ///         This is the auto-compound mechanism.
    function injectYield(uint256 hyUSDAmount) external onlyRole(VAULT_ROLE) {
        require(hyUSDAmount > 0, "SP: zero yield");
        hyUSD.safeTransferFrom(msg.sender, address(this), hyUSDAmount);
        hyUSDBalance += hyUSDAmount;

        emit YieldInjected(hyUSDAmount, sharePrice());
    }

    // ─── Drawdown (Mode 2 — CR < 130%) ───────────────────────────────────

    /// @notice Protocol draws down Stability Pool to restore CR.
    ///         Burns pool's hyUSD → reduces hyUSD supply → CR rises.
    ///         Mints equivalent xETH into pool → holders keep economic exposure.
    ///
    ///         Called by HyloVault when CR < CR_MODE1 (130%).
    ///
    /// @param hyUSDToBurn     Amount of pool hyUSD to burn (must be <= hyUSDBalance)
    /// @param xETHToMint      Equivalent xETH to deposit into pool
    ///                        (calculated by vault: xETHToMint = hyUSDToBurn / xETH price)
    function drawdown(
        uint256 hyUSDToBurn,
        uint256 xETHToMint
    ) external onlyRole(VAULT_ROLE) nonReentrant {
        require(hyUSDToBurn <= hyUSDBalance, "SP: insufficient hyUSD in pool");
        require(hyUSDToBurn > 0 && xETHToMint > 0, "SP: zero amounts");

        // Burn hyUSD from pool — this reduces circulating hyUSD supply
        // The actual burn call goes through HyUSD token (vault has MINTER_ROLE)
        // Here we just update accounting; vault already called hyUSD.burn() before this
        hyUSDBalance -= hyUSDToBurn;

        // Receive xETH minted by vault into this pool
        IERC20(address(xETH)).safeTransferFrom(
            msg.sender,
            address(this),
            xETHToMint
        );
        xETHBalance += xETHToMint;

        // Note: totalShares (shyUSD supply) does NOT change.
        // Each share now represents less hyUSD but some xETH.
        // Net: holders took on ETH price risk in exchange for higher CR protection.

        emit DrawdownExecuted(hyUSDToBurn, xETHToMint, 0); // CR emitted by vault
    }

    // ─── View Helpers ─────────────────────────────────────────────────────

    /// @notice Total pool size in hyUSD terms (xETH excluded — price-dependent)
    function totalHyUSD() external view returns (uint256) {
        return hyUSDBalance;
    }

    /// @notice Total xETH in pool from past drawdowns
    function totalXETH() external view returns (uint256) {
        return xETHBalance;
    }

    /// @notice hyUSD value a given shares amount can claim
    function previewWithdrawHyUSD(
        uint256 shares
    ) external view returns (uint256) {
        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) return 0;
        return (hyUSDBalance * shares) / supply;
    }
}
