// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "../interfaces/ICompound.sol";
import "../libraries/LibFarmStorage.sol";
import "./BaseFacet.sol";

contract CompoundFacet is BaseFacet, ReEntrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event EtherSupplied(uint _mintResult, uint256 _amount);
    event TokenSupplied(uint _mintResult, uint256 _amount);
    event RedeemFinished(uint256 _redeemResult, uint256 _amount);

    function supplyToken(
        address _tokenAddress,
        uint256 _amountToSupply
    )
        external
        onlyRegisteredAccount
        onlySupportedToken(_tokenAddress)
        noReentrant
        returns (uint)
    {
        if (_amountToSupply == 0) revert InvalidSupplyAmount();

        IERC20 underlyingToken = IERC20(_tokenAddress);

        if (underlyingToken.balanceOf(msg.sender) < _amountToSupply)
            revert InsufficientUserBalance();

        uint8 poolIndex = getPoolIndexFromToken(_tokenAddress);

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[poolIndex];

        address cTokenAddress;
        uint256 depositAmount;

        {
            uint256 leverageAmount = _amountToSupply.mul(
                LibFarmStorage.LEVERAGE_LEVEL
            );

            if (pool.balanceAmount < leverageAmount)
                revert InsufficientPoolBalance();

            depositAmount = _amountToSupply + leverageAmount;
            // Transfer tokens from sender to this contract
            underlyingToken.safeTransferFrom(
                msg.sender,
                address(this),
                _amountToSupply
            );

            LibFarmStorage.Depositor storage depositor = fs.depositors[
                poolIndex
            ][msg.sender];

            cTokenAddress = pool.cTokenAddress;

            pool.balanceAmount -= leverageAmount;
            pool.borrowAmount += leverageAmount;

            depositor.exchangeRate = CErc20(cTokenAddress)
                .exchangeRateCurrent();
            depositor.depositAmount[cTokenAddress] += _amountToSupply;
            depositor.debtAmount[cTokenAddress] += leverageAmount;
        }

        // Approve transfer on the ERC20 contract
        underlyingToken.safeApprove(cTokenAddress, depositAmount);

        uint256 balanceBeforeMint;
        uint256 balanceDiff;
        uint mintResult;

        {
            // Create a reference to the corresponding cToken contract, like cUSDC, cUSDT
            CErc20 cToken = CErc20(cTokenAddress);

            balanceBeforeMint = cToken.balanceOf(address(this));

            // Mint cTokens
            mintResult = cToken.mint(depositAmount);

            balanceDiff = cToken.balanceOf(address(this)) - balanceBeforeMint;
        }

        {
            LibFarmStorage.Depositor storage depositor = fs.depositors[
                poolIndex
            ][msg.sender];
            depositor.stakeAmount[cTokenAddress] += balanceDiff;
        }

        pool.stakeAmount += balanceDiff;

        emit TokenSupplied(mintResult, depositAmount);

        return mintResult;
    }

    function redeemCErc20Tokens(
        address _cTokenAddress,
        uint256 _amount,
        bool redeemType
    )
        external
        onlyRegisteredAccount
        onlySupportedCToken(_cTokenAddress)
        noReentrant
        returns (bool)
    {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool;
        LibFarmStorage.Depositor storage depositor;

        {
            uint8 poolIndex = getPoolIndexFromCToken(_cTokenAddress);

            pool = fs.pools[poolIndex];
            depositor = fs.depositors[poolIndex][msg.sender];
        }

        if (depositor.stakeAmount[_cTokenAddress] < _amount)
            revert InsufficientUserBalance();

        uint256 withdrawAmount;
        uint256 withdrawDebtAmount;

        {
            // Create a reference to the corresponding cToken contract, like cUSDC, cUSDT
            if (CErc20(_cTokenAddress).balanceOf(address(this)) < _amount)
                revert InsufficientPoolBalance();

            uint256 totalAmount = depositor.debtAmount[_cTokenAddress].add(
                depositor.depositAmount[_cTokenAddress]
            );

            withdrawAmount = _amount
                .mul(CErc20(_cTokenAddress).exchangeRateCurrent())
                .div(1e18);

            withdrawDebtAmount = withdrawAmount
                .mul(depositor.debtAmount[_cTokenAddress])
                .div(totalAmount);

            depositor.stakeAmount[_cTokenAddress] -= _amount;
            depositor.depositAmount[_cTokenAddress] -= withdrawAmount
                .mul(depositor.depositAmount[_cTokenAddress])
                .div(totalAmount);
            depositor.debtAmount[_cTokenAddress] -= withdrawDebtAmount;

            uint256 totalRewardAmount = withdrawAmount.sub(
                _amount.mul(depositor.exchangeRate).div(1e18)
            );

            if (totalRewardAmount > 0) {
                uint256 rewardAmount = totalRewardAmount.mul(totalAmount).div(
                    pool.stakeAmount
                );

                uint256 lpReward = rewardAmount.mul(fs.interestRate).div(100);

                pool.rewardAmount += lpReward;
                depositor.rewardAmount += rewardAmount.sub(lpReward);
            }
        }

        pool.balanceAmount += withdrawDebtAmount;
        pool.borrowAmount -= withdrawDebtAmount;
        pool.stakeAmount -= _amount;

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = CErc20(_cTokenAddress).redeem(_amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = CErc20(_cTokenAddress).redeemUnderlying(_amount);
        }

        emit RedeemFinished(redeemResult, _amount);

        return true;
    }
}
