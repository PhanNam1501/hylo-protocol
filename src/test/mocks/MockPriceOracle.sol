// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    uint256 public price; // 8 decimals
    uint256 public updatedAt;

    function setPrice(uint256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function getETHUSDPrice() external view override returns (uint256, uint256) {
        require(price != 0, "MockPriceOracle: price not set");
        return (price, updatedAt);
    }
}

