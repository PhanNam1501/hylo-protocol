// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IPriceOracle.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function decimals() external view returns (uint8);
}

/// @title ChainlinkPriceOracle
/// @notice Wraps Chainlink ETH/USD feed with staleness check.
///         This is the ONLY external oracle in the protocol — same as Hylo's SOL/USD.
contract ChainlinkPriceOracle is IPriceOracle {
    AggregatorV3Interface public immutable feed;
    uint256 public constant STALE_THRESHOLD = 1 hours;

    // Base mainnet: ETH/USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70
    constructor(address _feed) {
        feed = AggregatorV3Interface(_feed);
    }

    /// @inheritdoc IPriceOracle
    function getETHUSDPrice() external view override returns (uint256 price, uint256 updatedAt) {
        (, int256 answer, , uint256 _updatedAt, ) = feed.latestRoundData();
        require(answer > 0, "Oracle: invalid price");
        require(block.timestamp - _updatedAt <= STALE_THRESHOLD, "Oracle: stale price");

        // Chainlink ETH/USD is 8 decimals — return as-is
        price = uint256(answer);
        updatedAt = _updatedAt;
    }
}
