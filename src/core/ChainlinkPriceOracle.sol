// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/core/IPriceOracle.sol";

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
/// @notice Chainlink ETH/USD oracle wrapper with staleness checks.
contract ChainlinkPriceOracle is IPriceOracle {
    AggregatorV3Interface public immutable feed;
    uint256 public constant STALE_THRESHOLD = 1 hours;

    constructor(address _feed) {
        feed = AggregatorV3Interface(_feed);
    }

    /// @inheritdoc IPriceOracle
    function getETHUSDPrice() external view override returns (uint256 price, uint256 updatedAt) {
        (, int256 answer, , uint256 _updatedAt, ) = feed.latestRoundData();
        require(answer > 0, "Oracle: invalid price");
        require(block.timestamp - _updatedAt <= STALE_THRESHOLD, "Oracle: stale price");

        price = uint256(answer);
        updatedAt = _updatedAt;
    }
}
