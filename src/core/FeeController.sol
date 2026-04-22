// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/BloomMath.sol";
import "../interfaces/core/IFeeController.sol";

/// @title FeeController
/// @notice Returns dynamic protocol fees based on collateral ratio.
contract FeeController is Ownable, IFeeController {
    using BloomMath for uint256;

    uint256 public constant CR_HEALTHY = 1.5e18;
    uint256 public constant CR_MODE1 = 1.3e18;
    uint256 public constant CR_CRITICAL = 1.0e18;

    uint256 public bloomUSDMintFeeHealthy = 0.001e18;
    uint256 public bloomUSDRedeemFeeHealthy = 0.001e18;
    uint256 public xNativeMintFeeHealthy = 0.001e18;
    uint256 public xNativeRedeemFeeHealthy = 0.001e18;

    uint256 public bloomUSDMintFeeMode1 = 0.01e18;
    uint256 public bloomUSDRedeemFeeMode1 = 0.0e18;
    uint256 public xNativeMintFeeMode1 = 0.0e18;
    uint256 public xNativeRedeemFeeMode1 = 0.01e18;

    uint256 public bloomUSDMintFeeMode2 = 0.05e18;
    uint256 public bloomUSDRedeemFeeMode2 = 0.0e18;
    uint256 public xNativeMintFeeMode2 = 0.0e18;
    uint256 public xNativeRedeemFeeMode2 = 0.05e18;

    event ModeChanged(StabilityMode newMode, uint256 cr);

    constructor(address _owner) Ownable(_owner) {}

    function getMode(uint256 cr) public pure override returns (StabilityMode) {
        if (cr >= CR_HEALTHY) return StabilityMode.HEALTHY;
        if (cr >= CR_MODE1) return StabilityMode.MODE1;
        return StabilityMode.MODE2;
    }

    function getBloomUSDMintFee(uint256 cr) external view override returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return bloomUSDMintFeeHealthy;
        if (mode == StabilityMode.MODE1) return bloomUSDMintFeeMode1;
        return bloomUSDMintFeeMode2;
    }

    function getBloomUSDRedeemFee(uint256 cr) external view override returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return bloomUSDRedeemFeeHealthy;
        if (mode == StabilityMode.MODE1) return bloomUSDRedeemFeeMode1;
        return bloomUSDRedeemFeeMode2;
    }

    function getXNativeMintFee(uint256 cr) external view override returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return xNativeMintFeeHealthy;
        if (mode == StabilityMode.MODE1) return xNativeMintFeeMode1;
        return xNativeMintFeeMode2;
    }

    function getXNativeRedeemFee(uint256 cr) external view override returns (uint256) {
        StabilityMode mode = getMode(cr);
        if (mode == StabilityMode.HEALTHY) return xNativeRedeemFeeHealthy;
        if (mode == StabilityMode.MODE1) return xNativeRedeemFeeMode1;
        return xNativeRedeemFeeMode2;
    }

    /// @notice Apply fee to an amount: returns (net, feeAmount)
    function applyFee(uint256 amount, uint256 feeBps) external pure override returns (uint256 net, uint256 feeAmount) {
        feeAmount = BloomMath.wadMul(amount, feeBps);
        net = amount - feeAmount;
    }

    function setHealthyFees(uint256 mintBloomUSD, uint256 redeemBloomUSD, uint256 mintXNative, uint256 redeemXNative)
        external
        override
        onlyOwner
    {
        require(mintBloomUSD <= 0.05e18 && redeemBloomUSD <= 0.05e18, "Fee too high");
        require(mintXNative <= 0.05e18 && redeemXNative <= 0.05e18, "Fee too high");
        bloomUSDMintFeeHealthy = mintBloomUSD;
        bloomUSDRedeemFeeHealthy = redeemBloomUSD;
        xNativeMintFeeHealthy = mintXNative;
        xNativeRedeemFeeHealthy = redeemXNative;
    }
}
