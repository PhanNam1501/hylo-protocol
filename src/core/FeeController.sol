// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/HyloMath.sol";

/// @title FeeController
/// @notice Returns dynamic protocol fees based on collateral ratio.
contract FeeController is Ownable {
    using HyloMath for uint256;

    uint256 public constant CR_HEALTHY = 1.5e18;
    uint256 public constant CR_MODE1 = 1.3e18;
    uint256 public constant CR_CRITICAL = 1.0e18;

    uint256 public hyUSDMintFeeHealthy = 0.001e18;
    uint256 public hyUSDRedeemFeeHealthy = 0.001e18;
    uint256 public xETHMintFeeHealthy = 0.001e18;
    uint256 public xETHRedeemFeeHealthy = 0.001e18;

    uint256 public hyUSDMintFeeMode1 = 0.01e18;
    uint256 public hyUSDRedeemFeeMode1 = 0.0e18;
    uint256 public xETHMintFeeMode1 = 0.0e18;
    uint256 public xETHRedeemFeeMode1 = 0.01e18;

    uint256 public hyUSDMintFeeMode2 = 0.05e18;
    uint256 public hyUSDRedeemFeeMode2 = 0.0e18;
    uint256 public xETHMintFeeMode2 = 0.0e18;
    uint256 public xETHRedeemFeeMode2 = 0.05e18;

    enum StabilityMode {
        HEALTHY,
        MODE1,
        MODE2
    }

    event ModeChanged(StabilityMode newMode, uint256 cr);

    constructor(address _owner) Ownable(_owner) {}

    function getMode(uint256 cr) public pure returns (StabilityMode) {
        if (cr >= CR_HEALTHY) return StabilityMode.HEALTHY;
        if (cr >= CR_MODE1) return StabilityMode.MODE1;
        return StabilityMode.MODE2;
    }

    function getHyUSDMintFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return hyUSDMintFeeHealthy;
        if (mode == StabilityMode.MODE1) return hyUSDMintFeeMode1;
        return hyUSDMintFeeMode2;
    }

    function getHyUSDRedeemFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return hyUSDRedeemFeeHealthy;
        if (mode == StabilityMode.MODE1) return hyUSDRedeemFeeMode1;
        return hyUSDRedeemFeeMode2;
    }

    function getXETHMintFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return xETHMintFeeHealthy;
        if (mode == StabilityMode.MODE1) return xETHMintFeeMode1;
        return xETHMintFeeMode2;
    }

    function getXETHRedeemFee(uint256 cr) external view returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return xETHRedeemFeeHealthy;
        if (mode == StabilityMode.MODE1) return xETHRedeemFeeMode1;
        return xETHRedeemFeeMode2;
    }

    /// @notice Apply fee to an amount: returns (net, feeAmount)
    function applyFee(uint256 amount, uint256 feeBps) external pure returns (uint256 net, uint256 feeAmount) {
        feeAmount = HyloMath.wadMul(amount, feeBps);
        net = amount - feeAmount;
    }

    function setHealthyFees(uint256 mintHyUSD, uint256 redeemHyUSD, uint256 mintXETH, uint256 redeemXETH)
        external
        onlyOwner
    {
        require(mintHyUSD <= 0.05e18 && redeemHyUSD <= 0.05e18, "Fee too high");
        require(mintXETH <= 0.05e18 && redeemXETH <= 0.05e18, "Fee too high");
        hyUSDMintFeeHealthy = mintHyUSD;
        hyUSDRedeemFeeHealthy = redeemHyUSD;
        xETHMintFeeHealthy = mintXETH;
        xETHRedeemFeeHealthy = redeemXETH;
    }
}
