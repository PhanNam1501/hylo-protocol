// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title HyloMath
/// @notice Fixed-point math helpers for protocol calculations.
library HyloMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant USD_DECIMALS = 1e8;

    /// @notice WAD multiply: (a * b) / WAD
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / WAD;
    }

    /// @notice WAD divide: (a * WAD) / b
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "HyloMath: div by zero");
        return (a * WAD) / b;
    }

    /// @notice RAY multiply
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / RAY;
    }

    /// @notice RAY divide
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "HyloMath: div by zero");
        return (a * RAY) / b;
    }

    /// @notice Converts ETH amount (WAD) to USD value (WAD).
    function ethToUSD(uint256 ethAmount, uint256 ethPrice) internal pure returns (uint256) {
        return (ethAmount * ethPrice) / USD_DECIMALS;
    }

    /// @notice Convert USD amount (WAD) → ETH (WAD)
    function usdToETH(uint256 usdAmount, uint256 ethPrice) internal pure returns (uint256) {
        require(ethPrice != 0, "HyloMath: zero price");
        return (usdAmount * USD_DECIMALS) / ethPrice;
    }

    /// @notice Returns hyUSD NAV denominated in ETH.
    function hyUSDNavInETH(uint256 ethPrice) internal pure returns (uint256) {
        return usdToETH(WAD, ethPrice);
    }

    /// @notice Returns collateral ratio in WAD.
    function collateralRatio(uint256 totalETH, uint256 fixedReserve) internal pure returns (uint256) {
        if (fixedReserve == 0) return type(uint256).max;
        return wadDiv(totalETH, fixedReserve);
    }

    /// @notice Returns effective leverage in WAD.
    function effectiveLeverage(uint256 totalETH, uint256 variableReserve) internal pure returns (uint256) {
        if (variableReserve == 0) return type(uint256).max;
        return wadDiv(totalETH, variableReserve);
    }
}
