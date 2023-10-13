// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "../src/facets/AccountFacet.sol";
import "../src/facets/AaveFacet.sol";
import "../src/facets/CompoundFacet.sol";

import "../src/AccountFactory.sol";
import "../src/LeverageFarming.sol";
import "./utils/Math.sol";

import {BaseSetup} from "./utils/BaseSetup.sol";
import {StateDeployDiamond} from "./utils/StateDeployDiamond.sol";

contract AccountFacetTest is BaseSetup, StateDeployDiamond {
    using SafeERC20 for IERC20;
    using Math for uint256;

    AccountFactory implementation;
    AccountFactory accFactory;
    LeverageFarming farming;

    UpgradeableBeacon beacon;
    BeaconProxy proxy;
    AccountFacet accFacet;

    event AccountCreated(address indexed);

    function setUp() public override(BaseSetup, StateDeployDiamond) {
        BaseSetup.setUp();
        StateDeployDiamond.setUp();

        implementation = new AccountFactory();

        beacon = new UpgradeableBeacon(address(implementation));
        proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSignature("initialize(address)", address(diamond))
        );

        accFactory = AccountFactory(payable(address(proxy)));
        farming = new LeverageFarming(address(diamond));
        LeverageFarmingFacet(address(diamond)).initLeverageFarming();

        accFacet = AccountFacet(address(diamond));
    }

    function test_createAccount() public {
        // Alice creates account
        vm.startPrank(alice);
        accFactory.createAccount();
        vm.stopPrank();
    }

    function test_depositToPool() public {
        // Alice creates account and deposits 500 USDC to USDC pool.
        vm.startPrank(alice);

        // Alice deposits 500 USDC to pool, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        accFacet.deposit(1, 500);

        // Alice creates an account
        accFactory.createAccount();

        // Alice deposits to invalid pool, so reverts
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        accFacet.deposit(3, 500);

        // Alice deposits 0 to pool, so reverts
        vm.expectRevert(BaseFacet.AmountZero.selector);
        accFacet.deposit(1, 0);

        uint256 aliceUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(
            address(alice)
        );
        uint256 poolUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(
            address(diamond)
        );

        // Alice deposits 500 USDC to pool
        usdc.approve(address(diamond), 500);
        accFacet.deposit(1, 500);

        assertEq(
            IERC20(USDC_ADDRESS).balanceOf(address(alice)),
            aliceUsdcBalance - 500
        );

        assertEq(
            IERC20(USDC_ADDRESS).balanceOf(address(diamond)),
            poolUsdcBalance + 500
        );

        vm.stopPrank();
    }

    function test_withdrawFromPool() public {
        vm.startPrank(alice);

        // Alice withdraw 500 USDC from pool, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        accFacet.withdraw(1, 500);

        // Alice creates an account
        accFactory.createAccount();

        // Alice deposits from invalid pool, so reverts
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        accFacet.withdraw(3, 500);

        vm.expectRevert(BaseFacet.ZeroAmountForWithdraw.selector);
        accFacet.withdraw(1, 0);

        // // Alice deposits 500 USDC to pool
        IERC20(USDC_ADDRESS).safeApprove(address(accFacet), 500);
        accFacet.deposit(1, 500);

        uint256 aliceUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(
            address(alice)
        );

        accFacet.withdraw(1, 500);
        assertEq(
            IERC20(USDC_ADDRESS).balanceOf(address(alice)),
            aliceUsdcBalance + 500
        );

        vm.stopPrank();
    }

    function test_liquidate() public {
        uint256 amount = 10000;

        // Alice liquidate without creating account
        vm.startPrank(alice);

        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        accFacet.liquidate(address(diamond), address(bob), 10, USDC_ADDRESS);

        // Alice create account and liquidate bob's one, but pool is not supported, revert
        accFactory.createAccount();
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        accFacet.liquidate(address(diamond), address(bob), 10, USDC_ADDRESS);

        // Alice is going to liquidate his one, should revert
        vm.expectRevert(BaseFacet.InvalidLiquidateUser.selector);
        accFacet.liquidate(address(diamond), address(alice), 10, USDC_ADDRESS);
        vm.stopPrank();

        depositTokenToPool(address(accFactory), USDC_ADDRESS, alice, 1500);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, carol, 6000);

        // Alice deposits 1000 USDC to Compound for leverage
        CompoundFacet compFacet = CompoundFacet(address(diamond));
        IERC20(USDC_ADDRESS).safeApprove(address(compFacet), amount.toE6());
        compFacet.supplyToken(1, 5, amount.toE6());

        skip(SKIP_FORWARD_PERIOD);

        vm.startPrank(bob);
        accFacet.liquidate(address(diamond), address(alice), 5000, USDC_ADDRESS);
        vm.stopPrank();
    }

    function test_claimReward() public {
        // Alice tries to get reward without creating account
        vm.startPrank(alice);
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        accFacet.claimReward(1);

        // Alice create account and liquidate bob's one, but pool is not supported, revert
        accFactory.createAccount();
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        accFacet.claimReward(3);

        // Alice is going to claim his reward, but no reward for him, should revert.
        vm.expectRevert(BaseFacet.NoReward.selector);
        accFacet.claimReward(1);

        vm.stopPrank();
    }
}
