// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "forge-std/console.sol";

import "../interfaces/IAave.sol";
import "./BaseFacet.sol";

import "../libraries/LibFarmStorage.sol";

contract AaveFacet is BaseFacet, ReEntrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address private constant AAVE_LENDING_POOL_ADDRESSES_PROVIDER =
        0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;

    /**
    @dev Allows a registered account to deposit tokens into an Aave pool.
    @param _poolIndex The index of the pool to deposit into.
    @param _amount The amount of tokens to deposit.
    **/
    function depositToAave(
        uint8 _poolIndex,
        uint256 _amount
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        // If user tries to deposit zero amount, should revert
        if (_amount == 0) revert InvalidDepositAmount();

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];

        IERC20 underlyingToken = IERC20(pool.tokenAddress);

        // If user hasn't enough balance, should revert
        if (underlyingToken.balanceOf(msg.sender) < _amount)
            revert InsufficientUserBalance();

        // Calculate leverage amount based on user's deposit amount
        uint256 leverageAmount = _amount.mul(LibFarmStorage.LEVERAGE_LEVEL);
        uint256 depositAmount = _amount.add(leverageAmount);

        // If pool hasn't sufficient balance, should revert
        if (pool.balanceAmount < leverageAmount)
            revert InsufficientPoolBalance();

        // Transfer tokens to dimaond proxy
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        address aTokenAddress = pool.aTokenAddress;

        // Update pool's balance, borrow amount
        pool.balanceAmount -= leverageAmount;
        pool.borrowAmount += leverageAmount;

        // Update depositor's deposit and debt amount
        depositor.depositAmount[aTokenAddress] += _amount;
        depositor.debtAmount[aTokenAddress] += leverageAmount;

        // Get AToken balance
        uint256 beforeATokenBalance = IERC20(aTokenAddress).balanceOf(
            address(this)
        );

        // Approve the Aave lending pool to spend the tokens
        underlyingToken.safeApprove(_lendingPool(), depositAmount);

        // Deposit tokens into Aave v2 lending pool
        ILendingPool(_lendingPool()).deposit(
            pool.tokenAddress,
            depositAmount,
            address(this),
            0
        );

        uint256 balanceDiff = IERC20(aTokenAddress)
            .balanceOf(address(this))
            .sub(beforeATokenBalance);

        // Update depositor's stake amount and pool's stake amount
        depositor.stakeAmount[aTokenAddress] += balanceDiff;
        pool.stakeAmount += balanceDiff;
    }

    /**
    @dev Allows a registered account to withdraw tokens from an Aave supported pool.
    @param _poolIndex The index of the pool to withdraw from.
    @param _amount The amount of tokens to withdraw.
    **/
    function withdrawFromAave(
        uint8 _poolIndex,
        uint256 _amount
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        // If depositor hasn't sufficient balance for withdraw, should revert
        if (depositor.stakeAmount[pool.aTokenAddress] < _amount)
            revert InsufficientUserBalance();

        IERC20 aToken = IERC20(pool.aTokenAddress);

        // If Pool hasn't sufficient AToken balance for withdraw, should revert
        if (aToken.balanceOf(address(this)) < _amount)
            revert InsufficientPoolBalance();

        // Calculates depositor's total debt amount
        uint256 totalAmount = depositor.debtAmount[pool.aTokenAddress].add(
            depositor.depositAmount[pool.aTokenAddress]
        );

        // Calculate withdraw amount based on depositor's amount and debt amount
        uint256 withdrawDebtAmount = _amount
            .mul(depositor.debtAmount[pool.aTokenAddress])
            .div(totalAmount);
        uint256 withdrawDepositAmount = _amount
            .mul(depositor.depositAmount[pool.aTokenAddress])
            .div(totalAmount);

        // Update depositor's stake, deposit and debt amount
        depositor.stakeAmount[pool.aTokenAddress] -= _amount;
        depositor.depositAmount[pool.aTokenAddress] -= withdrawDepositAmount;
        depositor.debtAmount[pool.aTokenAddress] -= withdrawDebtAmount;

        // Calculate Pool's total reward
        uint256 totalRewardAmount = IERC20(pool.aTokenAddress).balanceOf(
            address(this)
        ) - pool.stakeAmount;

        if (totalRewardAmount > 0) {
            // Calculate depositor's reward based on his stake amount
            uint256 rewardAmount = totalRewardAmount.mul(totalAmount).div(
                pool.stakeAmount
            );

            // Calculate lp's reward amount
            uint256 lpReward = rewardAmount.mul(fs.interestRate).div(100);

            // Update pool's balance including reward
            pool.balanceAmount += lpReward;
            // Update depositor's reward amount
            depositor.rewardAmount += rewardAmount.sub(lpReward);
        }

        // Update pool's balance, borrow and stake amount
        pool.balanceAmount += withdrawDebtAmount;
        pool.borrowAmount -= withdrawDebtAmount;
        pool.stakeAmount -= _amount;

        address lendingPoolAddr = _lendingPool();

        // Approve lending pool to spend your aTokens
        aToken.safeApprove(lendingPoolAddr, _amount);

        // Withdraw tokens from Aave v2 lending pool
        ILendingPool(lendingPoolAddr).withdraw(
            pool.tokenAddress,
            _amount,
            address(this)
        );

        // Transfer tokens to user
        IERC20(pool.tokenAddress).safeApprove(
            msg.sender,
            withdrawDepositAmount
        );
        IERC20(pool.tokenAddress).safeTransfer(
            msg.sender,
            withdrawDepositAmount
        );

        emit WithdrawFromAave(msg.sender, withdrawDepositAmount);
    }

    function _lendingPool() internal view returns (address) {
        return
            ILendingPoolAddressesProvider(AAVE_LENDING_POOL_ADDRESSES_PROVIDER)
                .getLendingPool();
    }
}
