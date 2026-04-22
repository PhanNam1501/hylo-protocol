// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPermit2, IAllowanceTransfer} from "permit2/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../tokens/ShyUSD.sol";
import "../tokens/XETH.sol";
import "../libraries/BloomMath.sol";
import "../interfaces/stability/IStabilityPool.sol";

/// @title StabilityPool
/// @notice Manages bloomUSD staking shares, yield injection, and drawdown accounting.
contract StabilityPool is ReentrancyGuard, AccessControl, IStabilityPool {
    using SafeERC20 for IERC20;
    using BloomMath for uint256;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IPermit2 public immutable permit2;
    IERC20 public immutable bloomUSD;
    XNative public immutable xNative;
    SBloomUSD public immutable sbloomUSD;

    uint256 public bloomUSDBalance;
    uint256 public xNativeBalance;

    event Deposited(address indexed user, uint256 bloomUSDAmount, uint256 sharesIssued);
    event Withdrawn(address indexed user, uint256 shares, uint256 bloomUSDOut, uint256 xNativeOut);
    event YieldInjected(uint256 bloomUSDAmount, uint256 newSharePrice);
    event DrawdownExecuted(uint256 bloomUSDBurned, uint256 xNativeMinted, uint256 newCR);

    constructor(address _bloomUSD, address _xNative, address _sbloomUSD, address _admin, address _permit2) {
        permit2 = IPermit2(_permit2);
        bloomUSD = IERC20(_bloomUSD);
        xNative = XNative(_xNative);
        sbloomUSD = SBloomUSD(_sbloomUSD);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Returns current sbloomUSD share price in RAY.
    function sharePrice() public view override returns (uint256) {
        uint256 supply = sbloomUSD.totalSupply();
        if (supply == 0) return BloomMath.RAY;
        return (bloomUSDBalance * BloomMath.RAY) / supply;
    }

    /// @notice Deposit bloomUSD -> receive sbloomUSD shares
    /// @param amount Amount of bloomUSD to deposit (WAD)
    function depositWithPermit2(
        uint160 amount,
        address owner,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature
    ) external override nonReentrant returns (uint256 shares) {
        require(amount > 0, "SP: zero amount");

        uint256 supply = sbloomUSD.totalSupply();
        if (supply == 0) {
            shares = amount;
        } else {
            shares = (amount * supply) / bloomUSDBalance;
        }
        require(shares > 0, "SP: zero shares");

        try permit2.permit(owner, permitSingle, signature) {} catch {}

        permit2.transferFrom(owner, address(this), amount, permitSingle.details.token);
        bloomUSDBalance += amount;
        sbloomUSD.mint(msg.sender, shares);

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Deposit bloomUSD -> receive sbloomUSD shares
    /// @param amount Amount of bloomUSD to deposit (WAD)
    function deposit(uint256 amount) external override nonReentrant returns (uint256 shares) {
        require(amount > 0, "SP: zero amount");

        uint256 supply = sbloomUSD.totalSupply();
        if (supply == 0) {
            shares = amount;
        } else {
            shares = (amount * supply) / bloomUSDBalance;
        }
        require(shares > 0, "SP: zero shares");

        bloomUSD.safeTransferFrom(msg.sender, address(this), amount);
        bloomUSDBalance += amount;
        sbloomUSD.mint(msg.sender, shares);

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Burn sbloomUSD shares -> receive pro-rata bloomUSD + xNative
    /// @param shares Amount of sbloomUSD to burn
    function withdraw(uint256 shares) external override nonReentrant returns (uint256 bloomUSDOut, uint256 xNativeOut) {
        require(shares > 0, "SP: zero shares");
        uint256 supply = sbloomUSD.totalSupply();
        require(shares <= supply, "SP: exceeds supply");

        bloomUSDOut = (bloomUSDBalance * shares) / supply;
        xNativeOut = (xNativeBalance * shares) / supply;

        sbloomUSD.burn(msg.sender, shares);
        bloomUSDBalance -= bloomUSDOut;
        if (xNativeOut > 0) xNativeBalance -= xNativeOut;

        if (bloomUSDOut > 0) bloomUSD.safeTransfer(msg.sender, bloomUSDOut);
        if (xNativeOut > 0) {
            IERC20(address(xNative)).safeTransfer(msg.sender, xNativeOut);
        }

        emit Withdrawn(msg.sender, shares, bloomUSDOut, xNativeOut);
    }

    /// @notice Injects harvested bloomUSD yield into the pool.
    function injectYield(uint256 bloomUSDAmount) external override onlyRole(VAULT_ROLE) {
        require(bloomUSDAmount > 0, "SP: zero yield");
        bloomUSD.safeTransferFrom(msg.sender, address(this), bloomUSDAmount);
        bloomUSDBalance += bloomUSDAmount;

        emit YieldInjected(bloomUSDAmount, sharePrice());
    }

    /// @notice Executes pool drawdown with bloomUSD burn and xNative addition.
    /// @param bloomUSDToBurn Amount of pool bloomUSD to burn.
    /// @param xNativeToMint Amount of xNative to add to the pool.
    function drawdown(uint256 bloomUSDToBurn, uint256 xNativeToMint) external override onlyRole(VAULT_ROLE) nonReentrant {
        require(bloomUSDToBurn <= bloomUSDBalance, "SP: insufficient bloomUSD in pool");
        require(bloomUSDToBurn > 0 && xNativeToMint > 0, "SP: zero amounts");

        bloomUSDBalance -= bloomUSDToBurn;

        IERC20(address(xNative)).safeTransferFrom(msg.sender, address(this), xNativeToMint);
        xNativeBalance += xNativeToMint;

        emit DrawdownExecuted(bloomUSDToBurn, xNativeToMint, 0);
    }

    /// @notice Returns total bloomUSD balance in the pool.
    function totalBloomUSD() external view override returns (uint256) {
        return bloomUSDBalance;
    }

    /// @notice Returns total xNative balance in the pool.
    function totalXNative() external view override returns (uint256) {
        return xNativeBalance;
    }

    /// @notice Previews bloomUSD claimable for a share amount.
    function previewWithdrawBloomUSD(uint256 shares) external view override returns (uint256) {
        uint256 supply = sbloomUSD.totalSupply();
        if (supply == 0) return 0;
        return (bloomUSDBalance * shares) / supply;
    }
}
