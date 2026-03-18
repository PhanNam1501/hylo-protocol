// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/HyloMath.sol";

/// @title FeeController
/// @notice Implements Hylo's dynamic fee system tied to Collateral Ratio thresholds.
///
///         CR > 150%  → HEALTHY    — standard fees on all operations
///         CR 130-150% → MODE 1    — discourage hyUSD mint, encourage hyUSD redeem + xETH mint
///         CR < 130%  → MODE 2    — aggressive; Stability Pool drawdown also kicks in
///
///         Fee encoding: WAD (1e18 = 100%)
///         E.g. 0.003e18 = 0.3% fee
///
///         Fee adjustments follow Hylo docs exactly:
///           Mint hyUSD fee:   normal → HIGH (discourage)
///           Redeem hyUSD fee: normal → LOW  (encourage burn)
///           Mint xETH fee:    normal → LOW  (encourage more xETH buffer)
///           Redeem xETH fee:  normal → HIGH (discourage reducing xETH supply)
contract FeeController is Ownable {
    using HyloMath for uint256;

    // ─── CR Thresholds (WAD) ───────────────────────────────────────────────
    uint256 public constant CR_HEALTHY  = 1.50e18; // 150%
    uint256 public constant CR_MODE1    = 1.30e18; // 130%
    uint256 public constant CR_CRITICAL = 1.00e18; // 100%

    // ─── Fee Tiers (WAD) ──────────────────────────────────────────────────
    // Healthy
    uint256 public hyUSDMintFeeHealthy   = 0.001e18; // 0.1%
    uint256 public hyUSDRedeemFeeHealthy = 0.001e18;
    uint256 public xETHMintFeeHealthy    = 0.001e18;
    uint256 public xETHRedeemFeeHealthy  = 0.001e18;

    // Mode 1 (CR 130–150%)
    uint256 public hyUSDMintFeeMode1     = 0.010e18; // 1.0%  ← raised
    uint256 public hyUSDRedeemFeeMode1   = 0.000e18; // 0%    ← free
    uint256 public xETHMintFeeMode1      = 0.000e18; // 0%    ← free
    uint256 public xETHRedeemFeeMode1    = 0.010e18; // 1.0%  ← raised

    // Mode 2 (CR < 130%)
    uint256 public hyUSDMintFeeMode2     = 0.050e18; // 5%    ← punitive
    uint256 public hyUSDRedeemFeeMode2   = 0.000e18; // 0%    ← free
    uint256 public xETHMintFeeMode2      = 0.000e18; // 0%    ← free
    uint256 public xETHRedeemFeeMode2    = 0.050e18; // 5%    ← punitive

    // ─── Stability Mode ───────────────────────────────────────────────────
    enum StabilityMode { HEALTHY, MODE1, MODE2 }

    event ModeChanged(StabilityMode newMode, uint256 cr);

    constructor(address _owner) Ownable(_owner) {}

    // ─── Mode Detection ───────────────────────────────────────────────────

    function getMode(uint256 cr) public pure returns (StabilityMode) {
        if (cr >= CR_HEALTHY) return StabilityMode.HEALTHY;
        if (cr >= CR_MODE1)   return StabilityMode.MODE1;
        return StabilityMode.MODE2;
    }

    // ─── Fee Getters ──────────────────────────────────────────────────────

    function getHyUSDMintFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return hyUSDMintFeeHealthy;
        if (mode == StabilityMode.MODE1)   return hyUSDMintFeeMode1;
        return hyUSDMintFeeMode2;
    }

    function getHyUSDRedeemFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return hyUSDRedeemFeeHealthy;
        if (mode == StabilityMode.MODE1)   return hyUSDRedeemFeeMode1;
        return hyUSDRedeemFeeMode2;
    }

    function getXETHMintFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return xETHMintFeeHealthy;
        if (mode == StabilityMode.MODE1)   return xETHMintFeeMode1;
        return xETHMintFeeMode2;
    }

    function getXETHRedeemFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return xETHRedeemFeeHealthy;
        if (mode == StabilityMode.MODE1)   return xETHRedeemFeeMode1;
        return xETHRedeemFeeMode2;
    }

    /// @notice Apply fee to an amount: returns (net, feeAmount)
    function applyFee(uint256 amount, uint256 feeBps) external pure returns (uint256 net, uint256 feeAmount) {
        feeAmount = HyloMath.wadMul(amount, feeBps);
        net = amount - feeAmount;
    }

    // ─── Admin ────────────────────────────────────────────────────────────

    function setHealthyFees(
        uint256 mintHyUSD, uint256 redeemHyUSD,
        uint256 mintXETH,  uint256 redeemXETH
    ) external onlyOwner {
        require(mintHyUSD <= 0.05e18 && redeemHyUSD <= 0.05e18, "Fee too high");
        require(mintXETH  <= 0.05e18 && redeemXETH  <= 0.05e18, "Fee too high");
        hyUSDMintFeeHealthy   = mintHyUSD;
        hyUSDRedeemFeeHealthy = redeemHyUSD;
        xETHMintFeeHealthy    = mintXETH;
        xETHRedeemFeeHealthy  = redeemXETH;
    }
}
