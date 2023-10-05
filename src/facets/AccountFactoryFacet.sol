// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "../interfaces/ICompoundFacet.sol";
import "../interfaces/IAaveFacet.sol";
import "../interfaces/ICurveFacet.sol";
import "../libraries/ReEntrancyGuard.sol";
import "../libraries/LibFarmStorage.sol";

import "./BaseFacet.sol";

contract AccountFactoryFacet is BaseFacet, ReEntrancyGuard {
    event AccountCreated(address indexed);
    error AccountAlreadyExist();

    /**
    @dev Creates a new account for the specified user.
    @param _user The address of the user to create an account for.
    */
    function createAccount(address _user) external {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (fs.accounts[_user] == true) return;

        fs.accounts[_user] = true;

        emit AccountCreated(_user);
    }
}
