// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/core/HyloVault.sol";
import "../src/core/FeeController.sol";
import "../src/stability/StabilityPool.sol";
import "../src/tokens/HyUSD.sol";
import "../src/tokens/XETH.sol";
import "../src/tokens/ShyUSD.sol";

import "../src/test/mocks/MockERC20.sol";
import "../src/test/mocks/MockLSTOracle.sol";
import "../src/test/mocks/MockPriceOracle.sol";

contract HyloInvariantTest is Test {
    uint256 internal constant WAD = 1e18;

    address internal admin = address(0xA11CE);
    address internal user = address(0xB0B);
    address internal treasury = address(0xTrea5ury);

    HyUSD internal hyUSD;
    XETH internal xETH;
    ShyUSD internal shyUSD;
    FeeController internal feeController;
    StabilityPool internal stabilityPool;
    HyloVault internal vault;

    MockERC20 internal lst;
    MockLSTOracle internal lstOracle;
    MockPriceOracle internal priceOracle;

    function setUp() external {
        vm.startPrank(admin);

        hyUSD = new HyUSD(admin);
        xETH = new XETH(admin);
        shyUSD = new ShyUSD(admin);

        feeController = new FeeController(admin);

        stabilityPool = new StabilityPool(address(hyUSD), address(xETH), address(shyUSD), admin);

        lstOracle = new MockLSTOracle();
        priceOracle = new MockPriceOracle();

        vault = new HyloVault(
            address(hyUSD),
            address(xETH),
            address(lstOracle),
            address(priceOracle),
            address(feeController),
            address(stabilityPool),
            treasury,
            admin
        );

        // Wire roles
        hyUSD.grantRole(hyUSD.MINTER_ROLE(), address(vault));
        xETH.grantRole(xETH.MINTER_ROLE(), address(vault));

        stabilityPool.grantRole(stabilityPool.VAULT_ROLE(), address(vault));
        shyUSD.grantRole(shyUSD.MINTER_ROLE(), address(stabilityPool));

        // Collateral
        lst = new MockERC20("Mock LST", "mLST", 18);
        vault.addLST(address(lst));

        // Oracle setup
        priceOracle.setPrice(100e8); // ETH = $100
        lstOracle.setRate(address(lst), 1e18); // 1 LST = 1 ETH

        vm.stopPrank();

        // Fund user
        lst.mint(user, 2_000 * WAD);
    }

    function _depositLST(address who, uint256 lstAmount) internal {
        vm.startPrank(who);
        lst.approve(address(vault), lstAmount);
        vm.stopPrank();
    }

    function test_xETH_price_residual_claim_and_leverage_examples() external {
        // Setup like doc:
        // Total collateral: 1000 ETH ($100k), hyUSD supply 60k, xETH supply 1000
        vm.startPrank(user);
        lst.approve(address(vault), 1_000 * WAD);
        vault.mintHyUSD(address(lst), 600 * WAD, 0); // deposit $60k
        vault.mintXETH(address(lst), 400 * WAD, 0);  // deposit $40k
        vm.stopPrank();

        assertEq(vault.getTotalETH(), 1_000 * WAD);
        assertEq(hyUSD.totalSupply(), 60_000 * WAD);

        // variable = 400 ETH at $100 → $40k
        (uint256 variableReserve, bool solvent) = vault.getVariableReserve();
        assertTrue(solvent);
        assertEq(variableReserve, 400 * WAD);

        // xETH supply should be 1000 (bootstrap nav 1 on first mint)
        assertEq(xETH.totalSupply(), 1_000 * WAD);

        // xETH NAV in ETH = 0.4 ETH => $40
        assertEq(vault.getXETHNavETH(), 0.4e18);

        // Effective leverage = total / variable = 1000/400 = 2.5x
        assertEq(vault.getEffectiveLeverage(), 2.5e18);
    }

    function test_mint_hyUSD_increases_effective_leverage_holds_xETH_price() external {
        vm.startPrank(user);
        lst.approve(address(vault), 1_000 * WAD);
        vault.mintHyUSD(address(lst), 600 * WAD, 0);
        vault.mintXETH(address(lst), 400 * WAD, 0);
        vm.stopPrank();

        uint256 xNavBefore = vault.getXETHNavETH();
        uint256 elBefore = vault.getEffectiveLeverage();
        assertEq(xNavBefore, 0.4e18);
        assertEq(elBefore, 2.5e18);

        // Mint extra hyUSD by depositing $10k (100 ETH @ $100)
        vm.startPrank(user);
        lst.approve(address(vault), 100 * WAD);
        vault.mintHyUSD(address(lst), 100 * WAD, 0);
        vm.stopPrank();

        // xETH NAV should remain unchanged; EL should increase.
        assertEq(vault.getXETHNavETH(), xNavBefore);
        assertGt(vault.getEffectiveLeverage(), elBefore);
    }

    function test_mint_xETH_decreases_effective_leverage_holds_xETH_price() external {
        vm.startPrank(user);
        lst.approve(address(vault), 1_000 * WAD);
        vault.mintHyUSD(address(lst), 600 * WAD, 0);
        vault.mintXETH(address(lst), 400 * WAD, 0);
        vm.stopPrank();

        uint256 xNavBefore = vault.getXETHNavETH();
        uint256 elBefore = vault.getEffectiveLeverage();

        // Mint extra xETH by depositing $10k (100 ETH)
        vm.startPrank(user);
        lst.approve(address(vault), 100 * WAD);
        vault.mintXETH(address(lst), 100 * WAD, 0);
        vm.stopPrank();

        assertEq(vault.getXETHNavETH(), xNavBefore);
        assertLt(vault.getEffectiveLeverage(), elBefore);
    }

    function test_harvest_mints_hyUSD_to_stability_pool_without_changing_xETH_nav() external {
        // Base setup
        vm.startPrank(user);
        lst.approve(address(vault), 1_000 * WAD);
        vault.mintHyUSD(address(lst), 600 * WAD, 0);
        vault.mintXETH(address(lst), 400 * WAD, 0);
        vm.stopPrank();

        // Stake 10k hyUSD into stability pool
        vm.startPrank(user);
        hyUSD.approve(address(stabilityPool), 10_000 * WAD);
        stabilityPool.deposit(10_000 * WAD);
        vm.stopPrank();

        uint256 xNavBefore = vault.getXETHNavETH();
        uint256 sharesPriceBefore = stabilityPool.sharePrice();

        // Simulate LST yield: rate increases 0.58% (100 -> 100.58)
        vm.prank(admin);
        lstOracle.setRate(address(lst), 1.0058e18);

        // Harvest (admin has HARVESTER_ROLE by constructor)
        vm.prank(admin);
        vault.harvest();

        // xETH NAV should remain the same (yield redirected into hyUSD minted to pool)
        assertEq(vault.getXETHNavETH(), xNavBefore);
        assertGt(stabilityPool.sharePrice(), sharesPriceBefore);
    }

    function test_drawdown_burns_pool_hyUSD_and_mints_xETH_into_pool_raising_CR() external {
        // Setup near Mode2 by dropping ETH price.
        vm.startPrank(user);
        lst.approve(address(vault), 1_000 * WAD);
        vault.mintHyUSD(address(lst), 600 * WAD, 0);
        vault.mintXETH(address(lst), 400 * WAD, 0);
        vm.stopPrank();

        // Move ETH price down to $70 to make CR ~ 116.7% (Mode2)
        vm.prank(admin);
        priceOracle.setPrice(70e8);

        // Stake hyUSD in pool so drawdown can burn it
        vm.startPrank(user);
        hyUSD.approve(address(stabilityPool), 10_000 * WAD);
        stabilityPool.deposit(10_000 * WAD);
        vm.stopPrank();

        uint256 crBefore = vault.getCollateralRatio();
        assertLt(crBefore, 1.30e18);

        vm.prank(user);
        vault.triggerDrawdown();

        uint256 crAfter = vault.getCollateralRatio();
        assertGt(crAfter, crBefore);
        assertGt(stabilityPool.totalXETH(), 0);
    }
}

