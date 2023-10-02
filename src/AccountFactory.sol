// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin-upgrade/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrade/contracts/security/ReentrancyGuardUpgradeable.sol";

import "./libraries/LibFarmStorage.sol";
import "./facets/AccountFactoryFacet.sol";
import "./VersionAware.sol";

contract AccountFactory is
    Ownable,
    Initializable,
    ReentrancyGuardUpgradeable,
    VersionAware
{
    address private diamond;

    error InvalidAddress();

    /**
    @dev Initializes the contract by setting the `diamond` address to the address passed as an argument.
    @dev Checks if the address is valid or not.
    @param _diamondAddress The address of the diamond contract.
    */
    function initialize(address _diamondAddress) external initializer {
        if (_diamondAddress == address(0)) revert InvalidAddress();

        versionAwareContractName = "Beacon Proxy Pattern: V1";
        diamond = _diamondAddress;
    }

    /**
    @dev Creates an account using the `AccountFactoryFacet` contract.
    */
    function createAccount() external {
        AccountFactoryFacet(diamond).createAccount(msg.sender);
    }

    function getContractNameWithVersion()
        public
        pure
        override
        returns (string memory)
    {
        return "Beacon Proxy Pattern: V1";
    }
}
