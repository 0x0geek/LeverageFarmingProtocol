// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "../src/facets/AccountFacet.sol";
import "../src/facets/AaveFacet.sol";
import "../src/AccountFactory.sol";
import "../src/LeverageFarming.sol";

import {BaseSetup} from "./utils/BaseSetup.sol";
import {StateDeployDiamond} from "./utils/StateDeployDiamond.sol";

contract LeverageFarmingFacetTest is BaseSetup, StateDeployDiamond {
    LeverageFarming farming;

    event AccountCreated(address indexed);

    function setUp() public override(BaseSetup, StateDeployDiamond) {
        BaseSetup.setUp();
        StateDeployDiamond.setUp();

        farming = new LeverageFarming(address(diamond));
        LeverageFarmingFacet(address(diamond)).initLeverageFarming();
    }

    function test_initLeverageFarming() public {
        // Alice is not contract's owner, trying to initialize protocol, should revert
        vm.startPrank(alice);

        vm.expectRevert(BaseFacet.InvalidOwner.selector);
        LeverageFarmingFacet(address(diamond)).initLeverageFarming();
        vm.stopPrank();

        // LeverageFarming protocol is already initialized, but trying to do it again, should revert
        vm.expectRevert(BaseFacet.AlreadyInitialized.selector);
        LeverageFarmingFacet(address(diamond)).initLeverageFarming();
    }

    function test_setOwner() public {
        // Alice is not contract's owner, trying to set owner, should revert
        vm.startPrank(alice);
        vm.expectRevert(BaseFacet.InvalidOwner.selector);
        LeverageFarmingFacet(address(diamond)).setOwner(address(alice));
        vm.stopPrank();

        LeverageFarmingFacet(address(diamond)).setOwner(address(bob));
    }

    function test_setInterestRate() public {
        // Alice is not contract's owner, trying to set interest rate, should revert
        vm.startPrank(alice);
        vm.expectRevert(BaseFacet.InvalidOwner.selector);
        LeverageFarmingFacet(address(diamond)).setInterestRate(95);
        vm.stopPrank();

        LeverageFarmingFacet(address(diamond)).setInterestRate(95);
    }

    function test_getInterestRate() public {
        LeverageFarmingFacet(address(diamond)).setInterestRate(80);

        uint8 interestRate = LeverageFarmingFacet(address(diamond))
            .getInterestRate();
        assertEq(80, interestRate);
    }

    function test_setSupportedToken() public {
        // Alice is not contract's owner, trying to set interest rate, should revert
        vm.startPrank(alice);
        vm.expectRevert(BaseFacet.InvalidOwner.selector);
        LeverageFarmingFacet(address(diamond)).setSupportedToken(0, true);
        vm.stopPrank();

        LeverageFarmingFacet(address(diamond)).setSupportedToken(0, true);
        bool isSupported = LeverageFarmingFacet(address(diamond))
            .isSupportedToken(0);

        assertEq(isSupported, true);
    }
}
