// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/facets/AccountFacet.sol";
import "../src/facets/CompoundFacet.sol";
import "../src/AccountFactory.sol";
import "../src/LeverageFarming.sol";

import "./utils/BaseSetup.sol";
import "./utils/StateDeployDiamond.sol";
import "./utils/Math.sol";

contract CompoundFacetTest is BaseSetup, StateDeployDiamond {
    using SafeERC20 for IERC20;
    using Math for uint256;

    AccountFactory implementation;
    AccountFactory accFactory;
    LeverageFarming farming;

    UpgradeableBeacon beacon;
    BeaconProxy proxy;

    event TokenSupplied(uint, uint256);
    event AccountCreated(address indexed);
    error MintError();
    error EnterMarketError();

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

    function test_supplyToken() public {
        uint8 leverageRate = 4;
        uint256 amount = 1000;

        CompoundFacet compFacet = CompoundFacet(address(diamond));

        // Alice is going to deposit Compound, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice deposits 100 USDC to Compound, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        compFacet.supplyToken(1, leverageRate, amount.toE6());

        // Alice creates account and deposit 1000 DAI to Compound, but trying with unsupported token, should revert.
        accFactory.createAccount();
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        compFacet.supplyToken(3, leverageRate, amount.toE6());

        // Alice deposits 0 USDC to Compound, should revert
        vm.expectRevert(BaseFacet.InvalidSupplyAmount.selector);
        compFacet.supplyToken(1, leverageRate, 0);

        uint256 aliceUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(alice);
        // Alice tries to deposit more amount than his balance, should revert
        vm.expectRevert(BaseFacet.InsufficientUserBalance.selector);
        compFacet.supplyToken(1, leverageRate, aliceUsdcBalance + 1);

        // Alice tries to leverage farming with 1000 USDC, but there is no enough balance in pool.
        IERC20(USDC_ADDRESS).safeApprove(address(compFacet), amount.toE6());
        vm.expectRevert(BaseFacet.InsufficientPoolBalance.selector);
        compFacet.supplyToken(1, leverageRate, amount.toE6());

        vm.stopPrank();

        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, carol, 6000);

        vm.startPrank(alice);
        IERC20(USDC_ADDRESS).safeApprove(address(compFacet), amount.toE6());
        compFacet.supplyToken(1, leverageRate, amount.toE6());
        vm.stopPrank();
    }

    function test_redeemCErc20Tokens() public {
        uint8 leverageRate = 4;
        depositTokenToPool(address(accFactory), USDC_ADDRESS, bob, 1000);
        depositTokenToPool(address(accFactory), USDC_ADDRESS, carol, 6000);

        uint256 amount = 1000;

        CompoundFacet compFacet = CompoundFacet(address(diamond));

        // Alice is going to deposit Compound, but he didn't create account yet, should revert
        vm.startPrank(alice);

        // Alice withdraw 1000 USDC from Compound, without creating account.
        vm.expectRevert(BaseFacet.InvalidAccount.selector);
        compFacet.redeemCErc20Tokens(1, amount.toE6(), true);

        // Alice creates account and deposit 1000 DAI to Compound, but trying with unsupported token, should revert.
        accFactory.createAccount();

        // Alice deposits 1000 USDC to Compound for leverage
        IERC20(USDC_ADDRESS).safeApprove(address(compFacet), amount.toE6());
        compFacet.supplyToken(1, leverageRate, amount.toE6());

        //Alice withdraw 1000 DAI from Compound, but it's not supported, should revert
        vm.expectRevert(BaseFacet.NotSupportedToken.selector);
        compFacet.redeemCErc20Tokens(3, amount.toE6(), true);
        vm.stopPrank();

        vm.startPrank(bob);

        {
            CEth cEth = CEth(CETHER_ADDRESS);
            Comptroller comptroller = Comptroller(COMPTROLLER_ADDRESS);
            CErc20 cToken = CErc20(CUSDC_ADDRESS);

            // Supply ETH as collateral, get cETH in return
            cEth.mint{value: 10 * ETHER_DECIMAL, gas: 250000}();

            // Enter the ETH market so you can borrow another type of asset
            address[] memory cTokens = new address[](1);
            cTokens[0] = CETHER_ADDRESS;

            uint256[] memory errors = comptroller.enterMarkets(cTokens);

            if (errors[0] != 0) revert EnterMarketError();

            // Borrow underlying
            uint256 numUnderlyingToBorrow = 12000;

            // Borrow, check the underlying balance for this contract's address
            cToken.borrow(numUnderlyingToBorrow.toE6());

            // Get the borrow balance
            cToken.borrowBalanceCurrent(address(this));
        }

        vm.stopPrank();

        vm.startPrank(alice);
        skip(SKIP_FORWARD_PERIOD);

        compFacet.redeemCErc20Tokens(1, 10000000, true);

        vm.stopPrank();
    }
}
