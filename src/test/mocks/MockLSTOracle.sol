// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../interfaces/ILSTOracle.sol";

contract MockLSTOracle is ILSTOracle {
    mapping(address => uint256) public rateWad; // ETH per LST, WAD

    function setRate(address lst, uint256 rate) external {
        rateWad[lst] = rate;
    }

    function getLSTRate(address lst) external view override returns (uint256 rate) {
        rate = rateWad[lst];
        require(rate != 0, "MockLSTOracle: rate not set");
    }
}

