// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./facets/LeverageFarmingFacet.sol";

contract LeverageFarming is Ownable, ReentrancyGuard {
    LeverageFarmingFacet private lfpFacet;

    constructor(address _diamondAddress) {
        lfpFacet = LeverageFarmingFacet(_diamondAddress);
        lfpFacet.setOwner(msg.sender);
    }
}
