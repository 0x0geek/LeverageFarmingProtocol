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

import "./utils/BaseSetup.sol";
import "./utils/StateDeployDiamond.sol";
import "./utils/Math.sol";

contract AaveFacetTest is BaseSetup, StateDeployDiamond {
    using SafeERC20 for IERC20;
    using Math for uint256;

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
        LeverageFarmingFacet(address(diamond)).setInterestRate(80);
    }

    function test_depositToAave() public {
        uint8 leverageRate = 4;
        uint256 amount = 1000;

        AaveFacet aveFacet = AaveFacet(address(diamond));

        // Alice is going to deposit Aave, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice deposits 100 USDC to Aave, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        aveFacet.depositToAave(1, leverageRate, amount.toE6());

        // Alice creates account and deposit 1000 DAI to Aave, but trying with unsupported token, should revert.
        accFactory.createAccount();
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        aveFacet.depositToAave(3, leverageRate, amount.toE6());

        // Alice deposits 0 USDC to Aave, should revert
        vm.expectRevert(BaseFacet.InvalidDepositAmount.selector);
        aveFacet.depositToAave(1, leverageRate, 0);

        uint256 aliceUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(alice);
        // Alice tries to deposit more amount than his balance, should revert
        vm.expectRevert(BaseFacet.InsufficientUserBalance.selector);
        aveFacet.depositToAave(1, leverageRate, aliceUsdcBalance + 1);

        vm.expectRevert(BaseFacet.InsufficientCollateral.selector);
        aveFacet.depositToAave(1, leverageRate, 10000);

        vm.stopPrank();

        depositTokenToPool(address(accFactory), USDT_ADDRESS, alice, 1500);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);

        vm.startPrank(alice);
        // Alice tries to leverage farming with 1000 USDC, but there is no enough balance in pool.
        IERC20(USDC_ADDRESS).safeApprove(address(aveFacet), amount.toE6());
        vm.expectRevert(BaseFacet.InsufficientPoolBalance.selector);
        aveFacet.depositToAave(1, leverageRate, amount.toE6());

        vm.stopPrank();

        depositTokenToPool(address(accFactory), USDT_ADDRESS, alice, 4500);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, carol, 6000);

        vm.startPrank(alice);
        IERC20(USDC_ADDRESS).safeApprove(address(aveFacet), amount.toE6());
        aveFacet.depositToAave(1, leverageRate, amount.toE6());
        vm.stopPrank();
    }

    function test_withdrawFromAave() public {
        uint8 leverageRate = 3;

        uint256 amount = 1000;
        uint256 withdrawAmount = 500;

        AaveFacet aveFacet = AaveFacet(address(diamond));

        // Alice is going to deposit Aave, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice deposits 100 USDC to Aave, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        aveFacet.withdrawFromAave(1, amount.toE6());

        vm.stopPrank();

        depositTokenToPool(address(accFactory), USDC_ADDRESS, alice, 1500);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, carol, 6000);

        vm.startPrank(alice);
        // Alice creates account and deposit 1000 DAI to Aave, but trying with unsupported token, should revert.
        accFactory.createAccount();

        // Alice deposit 1000 USDC to Aave for leverage
        IERC20(USDC_ADDRESS).safeApprove(address(aveFacet), amount.toE6());
        aveFacet.depositToAave(1, leverageRate, amount.toE6());

        // Alice withdraw 1000 DAI from Aave, but it's not supported, should revert
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        aveFacet.withdrawFromAave(3, withdrawAmount.toE6());

        skip(SKIP_FORWARD_PERIOD);

        aveFacet.withdrawFromAave(1, withdrawAmount.toE6());

        vm.stopPrank();
    }
}
