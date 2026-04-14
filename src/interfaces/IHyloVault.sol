// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IFeeController.sol";

interface IHyloVault {
    function getTotalETH() external view returns (uint256 totalETH);

    function getETHPrice() external view returns (uint256 price);

    function getHyUSDNavETH() external view returns (uint256);

    function getFixedReserve() external view returns (uint256);

    function getVariableReserve()
        external
        view
        returns (uint256 variableReserve, bool solvent);

    function getXETHNavETH() external view returns (uint256);

    function getCollateralRatio() external view returns (uint256 cr);

    function getEffectiveLeverage() external view returns (uint256);

    function getProtocolState()
        external
        view
        returns (
            uint256 totalETH,
            uint256 ethPrice,
            uint256 hyUSDNav,
            uint256 fixedReserve,
            uint256 variableReserve,
            uint256 xETHNav,
            uint256 cr,
            uint256 effectiveLeverage,
            IFeeController.StabilityMode mode
        );

    function mintHyUSD(
        address lst,
        uint256 lstAmount,
        uint256 minHyUSD
    ) external returns (uint256 hyUSDOut);

    function redeemHyUSD(
        uint256 hyUSDAmount,
        address lst,
        uint256 minLST
    ) external returns (uint256 lstOut);

    function mintXETH(
        address lst,
        uint256 lstAmount,
        uint256 minXETH
    ) external returns (uint256 xETHOut);

    function redeemXETH(
        uint256 xETHAmount,
        address lst,
        uint256 minLST
    ) external returns (uint256 lstOut);

    function harvest() external;

    function triggerDrawdown() external;

    function addLST(address lst) external;

    function removeLST(address lst) external;

    function setTreasury(address _treasury) external;

    function pause() external;

    function unpause() external;

    function getLSTCount() external view returns (uint256);
}
