// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPermit2, IAllowanceTransfer} from "permit2/interfaces/IPermit2.sol";
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

    IPermit2 public immutable permit2;
    IERC20 public immutable bloomUSd;
    XETH public immutable xNative;
    ShyUSD public immutable shyUSD;

    uint256 public bloomUSdBalance;
    uint256 public xNativeBalance;

    event Deposited(address indexed user, uint256 bloomUSdAmount, uint256 sharesIssued);
    event Withdrawn(address indexed user, uint256 shares, uint256 bloomUSdOut, uint256 xNativeOut);
    event YieldInjected(uint256 bloomUSdAmount, uint256 newSharePrice);
    event DrawdownExecuted(uint256 bloomUSdBurned, uint256 xNativeMinted, uint256 newCR);

    constructor(address _bloomUSd, address _xNative, address _shyUSD, address _admin, address _permit2) {
        permit2 = IPermit2(_permit2);
        bloomUSd = IERC20(_bloomUSd);
        xNative = XETH(_xNative);
        shyUSD = ShyUSD(_shyUSD);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Returns current shyUSD share price in RAY.
    function sharePrice() public view returns (uint256) {
        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) return HyloMath.RAY;
        return (bloomUSdBalance * HyloMath.RAY) / supply;
    }

    /// @notice Deposit hyUSD → receive shyUSD shares
    /// @param amount Amount of hyUSD to deposit (WAD)
    function depositWithPermit2(
        uint160 amount,
        address owner,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature
    ) external nonReentrant returns (uint256 shares) {
        require(amount > 0, "SP: zero amount");

        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) {
            shares = amount;
        } else {
            shares = (amount * supply) / bloomUSdBalance;
        }
        require(shares > 0, "SP: zero shares");

        try permit2.permit(owner, permitSingle, signature) {} catch {}

        permit2.transferFrom(owner, address(this), amount, permitSingle.details.token);
        bloomUSdBalance += amount;
        shyUSD.mint(msg.sender, shares);

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Deposit hyUSD → receive shyUSD shares
    /// @param amount Amount of hyUSD to deposit (WAD)
    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        require(amount > 0, "SP: zero amount");

        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) {
            shares = amount;
        } else {
            shares = (amount * supply) / bloomUSdBalance;
        }
        require(shares > 0, "SP: zero shares");

        bloomUSd.safeTransferFrom(msg.sender, address(this), amount);
        bloomUSdBalance += amount;
        shyUSD.mint(msg.sender, shares);

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Burn shyUSD shares → receive pro-rata hyUSD + xETH
    /// @param shares Amount of shyUSD to burn
    function withdraw(uint256 shares) external nonReentrant returns (uint256 bloomUSdOut, uint256 xNativeOut) {
        require(shares > 0, "SP: zero shares");
        uint256 supply = shyUSD.totalSupply();
        require(shares <= supply, "SP: exceeds supply");

        bloomUSdOut = (bloomUSdBalance * shares) / supply;
        xNativeOut = (xNativeBalance * shares) / supply;

        shyUSD.burn(msg.sender, shares);
        bloomUSdBalance -= bloomUSdOut;
        if (xNativeOut > 0) xNativeBalance -= xNativeOut;

        if (bloomUSdOut > 0) bloomUSd.safeTransfer(msg.sender, bloomUSdOut);
        if (xNativeOut > 0) {
            IERC20(address(xNative)).safeTransfer(msg.sender, xNativeOut);
        }

        emit Withdrawn(msg.sender, shares, bloomUSdOut, xNativeOut);
    }

    /// @notice Injects harvested hyUSD yield into the pool.
    function injectYield(uint256 bloomUSdAmount) external onlyRole(VAULT_ROLE) {
        require(bloomUSdAmount > 0, "SP: zero yield");
        bloomUSd.safeTransferFrom(msg.sender, address(this), bloomUSdAmount);
        bloomUSdBalance += bloomUSdAmount;

        emit YieldInjected(bloomUSdAmount, sharePrice());
    }

    /// @notice Executes pool drawdown with bloomUSd burn and xNative addition.
    /// @param bloomUSdToBurn Amount of pool bloomUSd to burn.
    /// @param xNativeToMint Amount of xNative to add to the pool.
    function drawdown(uint256 bloomUSdToBurn, uint256 xNativeToMint) external onlyRole(VAULT_ROLE) nonReentrant {
        require(bloomUSdToBurn <= bloomUSdBalance, "SP: insufficient bloomUSd in pool");
        require(bloomUSdToBurn > 0 && xNativeToMint > 0, "SP: zero amounts");

        bloomUSdBalance -= bloomUSdToBurn;

        IERC20(address(xNative)).safeTransferFrom(msg.sender, address(this), xNativeToMint);
        xNativeBalance += xNativeToMint;

        emit DrawdownExecuted(bloomUSdToBurn, xNativeToMint, 0);
    }

    /// @notice Returns total hyUSD balance in the pool.
    function totalBloomUSd() external view returns (uint256) {
        return bloomUSdBalance;
    }

    /// @notice Returns total xETH balance in the pool.
    function totalXNative() external view returns (uint256) {
        return xNativeBalance;
    }

    /// @notice Previews hyUSD claimable for a share amount.
    function previewWithdrawBloomUSd(uint256 shares) external view returns (uint256) {
        uint256 supply = shyUSD.totalSupply();
        if (supply == 0) return 0;
        return (bloomUSdBalance * shares) / supply;
    }
}
