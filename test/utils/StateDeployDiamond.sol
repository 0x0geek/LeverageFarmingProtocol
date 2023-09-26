// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/******************************************************************************\
* Authors: Timo Neumann <timo@fyde.fi>, Rohan Sundar <rohan@fyde.fi>
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
* Abstract Contracts for the shared setup of the tests
/******************************************************************************/

import "../../src/interfaces/IDiamondCut.sol";
import "../../src/facets/DiamondCutFacet.sol";
import "../../src/facets/DiamondLoupeFacet.sol";
import "../../src/facets/OwnershipFacet.sol";
import "../../src/facets/AaveFacet.sol";
import "../../src/facets/AccountFacet.sol";
import "../../src/facets/CompoundFacet.sol";
import "../../src/facets/CurveFacet.sol";
import "../../src/facets/AccountFactoryFacet.sol";
import "../../src/facets/LeverageFarmingFacet.sol";

import "../../src/Diamond.sol";
import "./HelperContract.sol";

import "forge-std/console.sol";

abstract contract StateDeployDiamond is HelperContract {
    //contract types of facets to be deployed
    Diamond diamond;

    //interfaces with Facet ABI connected to diamond address
    IDiamondLoupe ILoupe;
    IDiamondCut ICut;

    string[] facetNameList;
    address[] facetAddressList;
    IDiamond.FacetCut[] diamondFacetCutList;

    // deploys diamond and connects facets
    function setUp() public virtual {
        //deploy facets
        DiamondCutFacet dCutFacet = new DiamondCutFacet();
        DiamondLoupeFacet dLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownerFacet = new OwnershipFacet();
        AaveFacet aaveFacet = new AaveFacet();
        CompoundFacet compFacet = new CompoundFacet();
        CurveFacet crvFacet = new CurveFacet();
        AccountFacet accFacet = new AccountFacet();
        AccountFactoryFacet accFactoryFacet = new AccountFactoryFacet();
        LeverageFarmingFacet lfpFacet = new LeverageFarmingFacet();

        facetNameList = [
            "DiamondCutFacet",
            "DiamondLoupeFacet",
            "OwnershipFacet",
            "AaveFacet",
            "CompoundFacet",
            "CurveFacet",
            "AccountFacet",
            "AccountFactoryFacet",
            "LeverageFarmingFacet"
        ];

        facetAddressList = [
            address(dCutFacet),
            address(dLoupeFacet),
            address(ownerFacet),
            address(aaveFacet),
            address(compFacet),
            address(crvFacet),
            address(accFacet),
            address(accFactoryFacet),
            address(lfpFacet)
        ];

        // diamod arguments
        DiamondArgs memory _args = DiamondArgs({
            owner: address(this),
            init: address(0),
            initCalldata: " "
        });

        uint256 facetLength = facetAddressList.length;

        for (uint256 i; i != facetLength; ++i) {
            IDiamond.FacetCut memory facetCut = IDiamond.FacetCut({
                facetAddress: address(facetAddressList[i]),
                action: IDiamond.FacetCutAction.Add,
                functionSelectors: generateSelectors(facetNameList[i])
            });

            diamondFacetCutList.push(facetCut);
        }

        // deploy diamond
        diamond = new Diamond(diamondFacetCutList, _args);
    }
}
