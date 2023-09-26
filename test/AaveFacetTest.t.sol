// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/facets/AccountFacet.sol";
import "../src/facets/AaveFacet.sol";
import "../src/AccountFactory.sol";
import "../src/LeverageFarming.sol";

import {BaseSetup} from "./utils/BaseSetup.sol";
import {StateDeployDiamond} from "./utils/StateDeployDiamond.sol";

contract AaveFacetTest is BaseSetup, StateDeployDiamond {
    using SafeERC20 for IERC20;

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

    function test_depositToAave() public {
        AaveFacet aveFacet = AaveFacet(address(diamond));

        // Alice is going to deposit Aave, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice deposits 100 USDC to Aave, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        aveFacet.depositToAave(USDC_ADDRESS, 1000);

        // Alice creates account and deposit 1000 DAI to Aave, but trying with unsupported token, should revert.
        accFactory.createAccount();
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        aveFacet.depositToAave(DAI_ADDRESS, 1000);

        // Alice deposits 0 USDC to Aave, should revert
        vm.expectRevert(BaseFacet.InvalidDepositAmount.selector);
        aveFacet.depositToAave(USDC_ADDRESS, 0);

        uint256 aliceUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(
            address(alice)
        );
        // Alice tries to deposit more amount than his balance, should revert
        vm.expectRevert(BaseFacet.InsufficientUserBalance.selector);
        aveFacet.depositToAave(USDC_ADDRESS, aliceUsdcBalance + 1);

        // Alice tries to leverage farming with 1000 USDC, but there is no enough balance in pool.
        IERC20(USDC_ADDRESS).safeApprove(address(aveFacet), 1000);
        vm.expectRevert(BaseFacet.InsufficientPoolBalance.selector);
        aveFacet.depositToAave(USDC_ADDRESS, 1000);

        vm.stopPrank();

        depositTokenToPool();

        vm.startPrank(alice);
        IERC20(USDC_ADDRESS).safeApprove(address(aveFacet), 1000);
        aveFacet.depositToAave(USDC_ADDRESS, 1000);
        vm.stopPrank();

        // skip(SKIP_FORWARD_PERIOD);

        // uint256 aUsdcBalance = IERC20(AUSDC_ADDRESS).balanceOf(
        //     address(aveFacet)
        // );
    }

    function test_withdrawFromAave() public {
        depositTokenToPool();

        AaveFacet aveFacet = AaveFacet(address(diamond));

        // Alice is going to deposit Aave, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice deposits 100 USDC to Aave, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        aveFacet.withdrawFromAave(AUSDC_ADDRESS, 1000);

        // Alice creates account and deposit 1000 DAI to Aave, but trying with unsupported token, should revert.
        accFactory.createAccount();

        // Alice deposit 1000 USDC to Aave for leverage
        IERC20(USDC_ADDRESS).safeApprove(address(aveFacet), 1000);
        aveFacet.depositToAave(USDC_ADDRESS, 1000);

        // Alice withdraw 1000 DAI from Aave, but it's not supported, should revert
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        aveFacet.withdrawFromAave(DAI_ADDRESS, 1000);

        // aveFacet.withdrawFromAave(AUSDC_ADDRESS, 1000);

        vm.stopPrank();
    }

    function depositTokenToPool() internal {
        AccountFacet accFacet = AccountFacet(address(diamond));

        // Bob creates his account and deposit 5000 USDC to USDC pool.
        vm.startPrank(bob);
        accFactory.createAccount();
        IERC20(USDC_ADDRESS).safeApprove(address(accFacet), 5000);
        accFacet.deposit(1, 5000);
        vm.stopPrank();

        // Carol creates his account and deposit 10000 USDC to USDC pool.
        vm.startPrank(carol);
        accFactory.createAccount();
        IERC20(USDC_ADDRESS).safeApprove(address(accFacet), 10000);
        accFacet.deposit(1, 10000);
        vm.stopPrank();
    }
}
