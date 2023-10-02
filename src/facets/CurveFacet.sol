// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "../interfaces/ICurve.sol";
import "../libraries/LibFarmStorage.sol";
import "./BaseFacet.sol";

contract CurveFacet is BaseFacet, ReEntrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Deposit(address indexed _poolAddress, uint256 _amount);
    event Withdraw(address indexed _poolAddress, uint256[3] _amounts);

    /**
    @dev Deposits the specified amount of tokens into the specified Curve pool with leverage.
    @param _poolIndex The index of the Curve pool to deposit into.
    @param _crvData The data of the Curve pool to deposit into.
    @param _amount The amount of tokens to deposit.
    */
    function depositToCurve(
        uint8 _poolIndex,
        CurveData calldata _crvData,
        uint256 _amount
    )
        external
        onlyRegisteredAccount
        onlySupportedPool(_poolIndex)
        noReentrant
        returns (uint256)
    {
        // If pool index is not valid, should revert
        if (_poolIndex == 0) revert InvalidPool();

        // If user tries to deposit zero amount, should revert
        if (_amount == 0) revert InvalidDepositAmount();

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        // If user hasn't enough balance for deposit, should revert
        if (IERC20(pool.tokenAddress).balanceOf(msg.sender) < _amount)
            revert InsufficientUserBalance();

        // Calculates the leverage amount based on user's deposit amount.
        uint256 leverageAmount = _amount.mul(LibFarmStorage.LEVERAGE_LEVEL);

        // If pool hasn't enough balance for leverage amount, should revert
        if (pool.balanceAmount < leverageAmount)
            revert InsufficientPoolBalance();

        // Updates the pool's balance and borrow amount based on leverage amount.
        pool.balanceAmount -= leverageAmount;
        pool.borrowAmount += leverageAmount;

        // Updates depositor's deposit amount and debt amount
        depositor.depositAmount[pool.crvLpTokenAddress] += _amount;
        depositor.debtAmount[pool.crvLpTokenAddress] += leverageAmount;

        // Transfer tokens from sender to this contract (Diamond proxy contract)
        IERC20(pool.tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 lpTokenAmount;

        // Approve tokens for depositing to Curve pool
        IERC20(pool.tokenAddress).safeApprove(
            _crvData.poolAddress,
            _amount.add(leverageAmount)
        );

        // Deposit tokens into Curve pool
        if (_poolIndex == 1)
            lpTokenAmount = ICurvePool(_crvData.poolAddress).add_liquidity(
                [0, _amount.add(leverageAmount), 0],
                0,
                true
            );
        else if (_poolIndex == 2)
            lpTokenAmount = ICurvePool(_crvData.poolAddress).add_liquidity(
                [0, 0, _amount.add(leverageAmount)],
                0,
                true
            );

        // Update depositor's stake amount
        depositor.stakeAmount[pool.crvLpTokenAddress] += lpTokenAmount;

        // Update pool's stake amount
        pool.stakeAmount += lpTokenAmount;

        // Approve lp tokens to CRV pool gauge to get reward from Curve
        IERC20(_crvData.lpTokenAddress).safeApprove(
            address(_crvData.gaugeAddress),
            lpTokenAmount
        );

        // Deposit LP tokens into the Curve gauge pool.
        ILiquidityGauge(_crvData.gaugeAddress).deposit(lpTokenAmount);

        // Mint to get reward
        ICurveMinter(_crvData.minterAddress).mint(
            address(_crvData.gaugeAddress)
        );

        emit Deposit(_crvData.poolAddress, lpTokenAmount);

        return lpTokenAmount;
    }

    /** 
    @dev Allows a registered account to withdraw their deposited funds from a supported Curve pool
    @param _crvData The data of the Curve pool to deposit into.
    @param _amount The amount of tokens to deposit.
    */
    function withdrawFromCurve(
        uint8 _poolIndex,
        CurveData calldata _crvData,
        uint256 _amount
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        address lpTokenAddress = _crvData.lpTokenAddress;

        // If user hasn't enough balance for lp token, should revert.
        if (depositor.stakeAmount[lpTokenAddress] < _amount)
            revert InsufficientUserBalance();

        // If pool hasn't enough balance for withdraw, should revert
        if (pool.stakeAmount < _amount) revert InsufficientPoolBalance();

        // Calculates depositor's total debt amount
        uint256 totalAmount = depositor.debtAmount[lpTokenAddress].add(
            depositor.depositAmount[lpTokenAddress]
        );

        {
            // Mint to get reward
            ICurveMinter(_crvData.minterAddress).mint(
                address(_crvData.gaugeAddress)
            );

            // Calculates the reward got from Curve pool
            uint256 totalRewardAmount = IERC20(LibFarmStorage.CRV_TOKEN_ADDRESS)
                .balanceOf(address(this));

            if (totalRewardAmount > 0) {
                // Calculate depositor's reward based on his deposit amount and pool's total stake amount
                uint256 rewardAmount = totalRewardAmount.mul(totalAmount).div(
                    pool.stakeAmount
                );

                // Calculates Liquidity provider's reward from the reward.
                uint256 lpReward = rewardAmount.mul(fs.interestRate).div(100);

                // Update Liquidity provider's reward
                pool.rewardAmount += lpReward;

                // Update depositor's reward (reward - lpreward);
                depositor.rewardAmount += rewardAmount.sub(lpReward);
            }
        }

        // Approve lending pool to spend your aTokens
        ILiquidityGauge(_crvData.gaugeAddress).withdraw(_amount);

        uint256 withdrawDepositAmount;

        {
            // remove liquidity from Curve pool
            uint256 amount = ICurvePool(_crvData.poolAddress)
                .remove_liquidity_one_coin(
                    _amount,
                    int128(int8(_poolIndex)),
                    0
                );

            // Calculate depositor's debt amount based on the withdrawn amount
            uint256 withdrawDebtAmount = amount
                .mul(depositor.debtAmount[lpTokenAddress])
                .div(totalAmount);
            // Calculate's depositor's deposit amount based on the withdrawn amount
            withdrawDepositAmount = amount
                .mul(depositor.depositAmount[lpTokenAddress])
                .div(totalAmount);

            // Update pool's balance, borrow and stake amount
            pool.balanceAmount += withdrawDebtAmount;
            pool.borrowAmount -= withdrawDebtAmount;
            pool.stakeAmount -= _amount;

            // Update depositor's stake, debt and deposit amount
            depositor.stakeAmount[lpTokenAddress] -= amount;
            depositor.debtAmount[lpTokenAddress] -= withdrawDebtAmount;
            depositor.depositAmount[lpTokenAddress] -= withdrawDepositAmount;
        }

        // Transfer user's withdraw token
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
}
