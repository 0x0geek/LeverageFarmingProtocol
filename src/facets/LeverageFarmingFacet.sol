// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import "../libraries/LibFarmStorage.sol";
import "./BaseFacet.sol";

contract LeverageFarmingFacet is BaseFacet, ReentrancyGuard {
    /**
    @dev Initializes a farming contract by adding three pools to it, each with different tokens and addresses.
    @dev Sets the `initialized` flag in the `FarmStorage` struct to `true`.
    @dev Only the admin can call this function.
    */
    function initLeverageFarming() external onlyAdmin {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (fs.initialized) revert AlreadyInitialized();

        addPool(
            0,
            LibFarmStorage.ETHER_ADDRESS,
            LibFarmStorage.CETHER_ADDRESS,
            LibFarmStorage.AAVE_POOL_LP_TOKEN_ADDRESS,
            LibFarmStorage.AETHER_ADDRESS
        ); // Ether pool
        addPool(
            1,
            LibFarmStorage.USDC_ADDRESS,
            LibFarmStorage.CUSDC_ADDRESS,
            LibFarmStorage.AAVE_POOL_LP_TOKEN_ADDRESS,
            LibFarmStorage.AUSDC_ADDRESS
        ); // USDC pool
        addPool(
            2,
            LibFarmStorage.USDT_ADDRESS,
            LibFarmStorage.CUSDT_ADDRESS,
            LibFarmStorage.AAVE_POOL_LP_TOKEN_ADDRESS,
            LibFarmStorage.AUSDT_ADDRESS
        ); // USDT pool

        fs.initialized = true;
    }

    /**
    @dev Sets the owner of the farming contract to the address passed as an argument.
    @dev Only the admin can call this function.
    @param _owner The address of the new owner.
    */
    function setOwner(address _owner) external onlyAdmin {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        fs.owner = _owner;
    }

    /**
    @dev Sets the interest rate of the farming contract to the value passed as an argument.
    @param _interestRate The new interest rate.
    */
    function setInterestRate(uint8 _interestRate) external onlyAdmin {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        fs.interestRate = _interestRate;
    }

    /**
    @dev Returns the current interest rate of the farming contract.
    @return The current interest rate.
    */
    function getInterestRate() external view returns (uint8) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        return fs.interestRate;
    }

    /**
    @dev Sets the `supported` flag of a pool in the farming contract to the value passed as an argument.
    @param _poolIndex The index of the pool to be modified.
    @param _supported The new value of the `supported` flag.
    */
    function setSupportedToken(
        uint8 _poolIndex,
        bool _supported
    ) external onlyAdmin {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        if (pool.supported != _supported) pool.supported = _supported;
    }

    /**
    @dev Returns a boolean value indicating whether a pool in the farming contract is supported or not.
    @param _poolIndex which is the index of the pool to be checked.
    @return A boolean value indicating whether the pool is supported or not.
    */
    function isSupportedToken(uint8 _poolIndex) external view returns (bool) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        return pool.supported;
    }

    /**
    @dev Adds a new pool to the farming contract.
    @param _poolIndex The index of the new pool.
    @param _token The address of the token used in the pool.
    @param _cToken The address of the corresponding cToken.
    @param _crvLpToken The address of the Curve LP token.
    @param _aToken The address of the corresponding aToken.
    */
    function addPool(
        uint8 _poolIndex,
        address _token,
        address _cToken,
        address _crvLpToken,
        address _aToken
    ) internal {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        pool.tokenAddress = _token;
        pool.cTokenAddress = _cToken;
        pool.aTokenAddress = _aToken;
        pool.crvLpTokenAddress = _crvLpToken;
        pool.balanceAmount = 0;
        pool.interestAmount = 0;
        pool.borrowAmount = 0;
        pool.assetAmount = 0;
        pool.rewardAmount = 0;
        pool.supported = true;
    }
}
