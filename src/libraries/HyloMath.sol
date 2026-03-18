// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title HyloMath
/// @notice Fixed-point math helpers used throughout the protocol.
///         WAD = 1e18 (18 decimal precision — used for ETH/LST amounts)
///         RAY = 1e27 (27 decimal precision — used for share price)
///         USD  = 1e8  (Chainlink oracle precision)
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

    /// @notice Convert ETH amount (WAD) → USD value (WAD)
    ///         ethPrice is 8-decimal Chainlink price
    function ethToUSD(uint256 ethAmount, uint256 ethPrice) internal pure returns (uint256) {
        // ethAmount (1e18) * ethPrice (1e8) / 1e8 = USD in 1e18
        return (ethAmount * ethPrice) / USD_DECIMALS;
    }

    /// @notice Convert USD amount (WAD) → ETH (WAD)
    function usdToETH(uint256 usdAmount, uint256 ethPrice) internal pure returns (uint256) {
        require(ethPrice != 0, "HyloMath: zero price");
        // usdAmount (1e18) * 1e8 / ethPrice (1e8) = ETH in 1e18
        return (usdAmount * USD_DECIMALS) / ethPrice;
    }

    /// @notice hyUSD NAV in ETH: 1 USD worth of ETH
    ///         = 1e18 (WAD USD) / ethPrice → ETH per hyUSD
    function hyUSDNavInETH(uint256 ethPrice) internal pure returns (uint256) {
        // 1 USD = 1e18 in WAD representation
        return usdToETH(WAD, ethPrice);
    }

    /// @notice Collateral Ratio in WAD (1.0 WAD = 100%)
    ///         CR = totalETH / fixedReserve
    function collateralRatio(uint256 totalETH, uint256 fixedReserve) internal pure returns (uint256) {
        if (fixedReserve == 0) return type(uint256).max;
        return wadDiv(totalETH, fixedReserve);
    }

    /// @notice Effective Leverage in WAD
    ///         EL = totalETH / variableReserve
    function effectiveLeverage(uint256 totalETH, uint256 variableReserve) internal pure returns (uint256) {
        if (variableReserve == 0) return type(uint256).max;
        return wadDiv(totalETH, variableReserve);
    }
}
