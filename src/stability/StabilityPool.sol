// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../tokens/ShyUSD.sol";
import "../tokens/XETH.sol";
import "../libraries/HyloMath.sol";

/// @title StabilityPool
/// @notice Manages hyUSD staking shares, yield injection, and drawdown accounting.
contract StabilityPool is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using HyloMath for uint256;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 public immutable hyUSD;
    XETH public immutable xETH;
    ShyUSD public immutable shyUSD;

    uint256 public hyUSDBalance;
    uint256 public xETHBalance;

    event Deposited(
        address indexed user,
        uint256 hyUSDAmount,
        uint256 sharesIssued
    );
    event Withdrawn(
        address indexed user,
        uint256 shares,
        uint256 hyUSDOut,
        uint256 xETHOut
    );
    event YieldInjected(uint256 hyUSDAmount, uint256 newSharePrice);
    event DrawdownExecuted(
        uint256 hyUSDBurned,
        uint256 xETHMinted,
        uint256 newCR
    );

    constructor(
        address _hyUSD,
        address _xETH,
        address _shyUSD,
        address _admin
    ) {
        hyUSD = IERC20(_hyUSD);
        xETH = XETH(_xETH);
        shyUSD = ShyUSD(_shyUSD);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Returns current shyUSD share price in RAY.
    function sharePrice() public view returns (uint256) {
        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) return HyloMath.RAY;
        return (hyUSDBalance * HyloMath.RAY) / supply;
    }

    /// @notice Deposit hyUSD → receive shyUSD shares
    /// @param amount Amount of hyUSD to deposit (WAD)
    function deposit(
        uint256 amount
    ) external nonReentrant returns (uint256 shares) {
        require(amount > 0, "SP: zero amount");

        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) {
            shares = amount;
        } else {
            shares = (amount * supply) / hyUSDBalance;
        }
        require(shares > 0, "SP: zero shares");

        hyUSD.safeTransferFrom(msg.sender, address(this), amount);
        hyUSDBalance += amount;
        shyUSD.mint(msg.sender, shares);

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Burn shyUSD shares → receive pro-rata hyUSD + xETH
    /// @param shares Amount of shyUSD to burn
    function withdraw(
        uint256 shares
    ) external nonReentrant returns (uint256 hyUSDOut, uint256 xETHOut) {
        require(shares > 0, "SP: zero shares");
        uint256 supply = shyUSD.totalSupply();
        require(shares <= supply, "SP: exceeds supply");

        hyUSDOut = (hyUSDBalance * shares) / supply;
        xETHOut = (xETHBalance * shares) / supply;

        shyUSD.burn(msg.sender, shares);
        hyUSDBalance -= hyUSDOut;
        if (xETHOut > 0) xETHBalance -= xETHOut;

        if (hyUSDOut > 0) hyUSD.safeTransfer(msg.sender, hyUSDOut);
        if (xETHOut > 0)
            IERC20(address(xETH)).safeTransfer(msg.sender, xETHOut);

        emit Withdrawn(msg.sender, shares, hyUSDOut, xETHOut);
    }

    /// @notice Injects harvested hyUSD yield into the pool.
    function injectYield(uint256 hyUSDAmount) external onlyRole(VAULT_ROLE) {
        require(hyUSDAmount > 0, "SP: zero yield");
        hyUSD.safeTransferFrom(msg.sender, address(this), hyUSDAmount);
        hyUSDBalance += hyUSDAmount;

        emit YieldInjected(hyUSDAmount, sharePrice());
    }

    /// @notice Executes pool drawdown with hyUSD burn and xETH addition.
    /// @param hyUSDToBurn Amount of pool hyUSD to burn.
    /// @param xETHToMint Amount of xETH to add to the pool.
    function drawdown(
        uint256 hyUSDToBurn,
        uint256 xETHToMint
    ) external onlyRole(VAULT_ROLE) nonReentrant {
        require(hyUSDToBurn <= hyUSDBalance, "SP: insufficient hyUSD in pool");
        require(hyUSDToBurn > 0 && xETHToMint > 0, "SP: zero amounts");

        hyUSDBalance -= hyUSDToBurn;

        IERC20(address(xETH)).safeTransferFrom(
            msg.sender,
            address(this),
            xETHToMint
        );
        xETHBalance += xETHToMint;

        emit DrawdownExecuted(hyUSDToBurn, xETHToMint, 0);
    }

    /// @notice Returns total hyUSD balance in the pool.
    function totalHyUSD() external view returns (uint256) {
        return hyUSDBalance;
    }

    /// @notice Returns total xETH balance in the pool.
    function totalXETH() external view returns (uint256) {
        return xETHBalance;
    }

    /// @notice Previews hyUSD claimable for a share amount.
    function previewWithdrawHyUSD(
        uint256 shares
    ) external view returns (uint256) {
        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) return 0;
        return (hyUSDBalance * shares) / supply;
    }
}
