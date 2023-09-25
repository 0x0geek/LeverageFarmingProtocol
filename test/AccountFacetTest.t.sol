// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "../src/facets/AccountFacet.sol";
import "../src/facets/AaveFacet.sol";
import "../src/AccountFactory.sol";
import "../src/LeverageFarming.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {StateDeployDiamond} from "./StateDeployDiamond.sol";

contract AccountFacetTest is BaseSetup, StateDeployDiamond {
    AccountFactory implementation;
    AccountFactory accFactory;
    LeverageFarming farming;

    UpgradeableBeacon beacon;
    BeaconProxy proxy;

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
    }

    function test_createAccount() public {
        // Alice creates account
        vm.startPrank(alice);
        accFactory.createAccount();

        // Alice creates account again, but reverts because he already created account.
        vm.expectRevert(AccountFactoryFacet.AccountAlreadyExist.selector);
        accFactory.createAccount();
        vm.stopPrank();
    }

    function test_depositToPool() public {
        // Alice creates account and deposits 5 USDC to USDC pool.
        vm.startPrank(alice);

        // Alice deposits 5 USDC to pool, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        AccountFacet(address(diamond)).deposit(1, 5);

        // Alice creates an account
        accFactory.createAccount();

        // Alice deposits to invalid pool, so reverts
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        AccountFacet(address(diamond)).deposit(3, 5);

        // Alice deposits 0 to pool, so reverts
        vm.expectRevert(BaseFacet.AmountZero.selector);
        AccountFacet(address(diamond)).deposit(1, 0);

        // Alice deposits 5 USDC to pool
        usdc.approve(address(diamond), 5);
        AccountFacet(address(diamond)).deposit(1, 5);

        vm.stopPrank();
    }

    function test_withdrawFromPool() public {
        vm.startPrank(alice);

        // Alice withdraw 5 USDC from pool, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        AccountFacet(address(diamond)).withdraw(1, 5);

        // Alice creates an account
        accFactory.createAccount();

        address daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        // Alice deposits from invalid pool, so reverts
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        AccountFacet(address(diamond)).withdraw(3, 5);

        vm.expectRevert(BaseFacet.ZeroAmountForWithdraw.selector);
        AccountFacet(address(diamond)).withdraw(1, 5);

        vm.stopPrank();
    }

    function test_liquidate() public {
        // Alice liquidate without creating account
        vm.startPrank(alice);

        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        AccountFacet(address(diamond)).liquidate(address(bob), 1, 10);

        // Alice create account and liquidate bob's one, but pool is not supported, revert
        accFactory.createAccount();
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        AccountFacet(address(diamond)).liquidate(address(bob), 4, 10);
        
        // Alice is going to liquidate his one, should revert
        vm.expectRevert(BaseFacet.InvalidLiquidateUser.selector);
        AccountFacet(address(diamond)).liquidate(address(alice), 1, 10);
        vm.stopPrank();
    }
}
