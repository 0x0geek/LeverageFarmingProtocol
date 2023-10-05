// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/facets/AccountFacet.sol";
import "../src/facets/CurveFacet.sol";
import "../src/interfaces/ICurve.sol";
import "../src/AccountFactory.sol";
import "../src/LeverageFarming.sol";

import "./utils/BaseSetup.sol";
import "./utils/StateDeployDiamond.sol";
import "./utils/Math.sol";

contract CurveFacetTest is BaseSetup, StateDeployDiamond {
    using SafeERC20 for IERC20;
    using Math for uint256;

    AccountFactory implementation;
    AccountFactory accFactory;
    LeverageFarming farming;
    CurveData testCrvData;

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

        testCrvData = CurveData({
            poolAddress: AAVE_POOL_ADDRESS,
            gaugeAddress: AAVE_LIQUIDITY_GAUGE_ADDRESS,
            minterAddress: CRV_TOKEN_MINTER_ADDRESS,
            lpTokenAddress: AAVE_POOL_LP_TOKEN_ADDRESS
        });
    }

    function test_depositToCurve() public {
        uint8 leverageRate = 3;
        uint256 amount = 1000;

        CurveFacet crvFacet = CurveFacet(address(diamond));

        // Alice is going to deposit Curve, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice deposits 100 USDC to Aave, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        crvFacet.depositToCurve(1, leverageRate, testCrvData, amount.toE6());

        // Alice creates account and deposit 1000 DAI to Curve, but trying with unsupported token, should revert.
        accFactory.createAccount();
        vm.expectRevert(BaseFacet.InvalidPool.selector);
        crvFacet.depositToCurve(0, leverageRate, testCrvData, amount.toE6());

        // Alice deposits 0 USDC to Curve, should revert
        vm.expectRevert(BaseFacet.InvalidDepositAmount.selector);
        crvFacet.depositToCurve(1, leverageRate, testCrvData, 0);

        uint256 aliceUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(alice);
        IERC20(USDC_ADDRESS).safeApprove(
            address(crvFacet),
            aliceUsdcBalance + 1
        );
        // Alice tries to deposit more amount than his balance, should revert
        vm.expectRevert(BaseFacet.InsufficientUserBalance.selector);
        crvFacet.depositToCurve(
            1,
            leverageRate,
            testCrvData,
            aliceUsdcBalance + 1
        );

        vm.expectRevert(BaseFacet.InsufficientCollateral.selector);
        crvFacet.depositToCurve(1, leverageRate, testCrvData, amount.toE6());

        vm.stopPrank();

        depositTokenToPool(address(accFactory), USDT_ADDRESS, alice, 1500);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);

        vm.startPrank(alice);
        // Alice tries to leverage farming with 1000 USDC, but there is no enough balance in pool.
        IERC20(USDC_ADDRESS).safeApprove(address(crvFacet), amount.toE6());
        vm.expectRevert(BaseFacet.InsufficientPoolBalance.selector);
        crvFacet.depositToCurve(1, leverageRate, testCrvData, amount.toE6());

        vm.stopPrank();

        depositTokenToPool(address(accFactory), USDT_ADDRESS, alice, 4500);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, carol, 6000);

        vm.startPrank(alice);
        IERC20(USDC_ADDRESS).safeApprove(address(crvFacet), amount.toE6());
        crvFacet.depositToCurve(1, leverageRate, testCrvData, amount.toE6());
        vm.stopPrank();
    }

    function test_withdrawFromCurve() public {
        uint8 leverageRate = 2;

        depositTokenToPool(address(accFactory), USDC_ADDRESS, alice, 1500);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, carol, 6000);

        uint256 amount = 1000;
        uint256 withdrawAmount = 1000;

        CurveFacet crvFacet = CurveFacet(address(diamond));

        // Alice is going to deposit Curve, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice deposits 100 USDC to Curve, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        crvFacet.withdrawFromCurve(1, testCrvData, amount.toE6());

        // Alice creates account and deposit 1000 DAI to Curve, but trying with unsupported token, should revert.
        accFactory.createAccount();

        // Alice deposit 1000 USDC to Curve for leverage
        IERC20(USDC_ADDRESS).safeApprove(address(crvFacet), amount.toE6());
        crvFacet.depositToCurve(1, leverageRate, testCrvData, amount.toE6());

        // Alice withdraw 1000 DAI from Curve, but it's not supported, should revert
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        crvFacet.withdrawFromCurve(3, testCrvData, withdrawAmount);

        skip(SKIP_FORWARD_PERIOD);

        crvFacet.withdrawFromCurve(1, testCrvData, withdrawAmount);

        vm.stopPrank();
    }
}
