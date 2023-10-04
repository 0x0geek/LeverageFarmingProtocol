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

    /**
    @dev Allows a registered account to supply tokens to Compound.
    @param _poolIndex The index of the pool to supply tokens to.
    @param _leverageRate The Leverage Rate.
    @param _amountToSupply The amount of tokens to supply.
    **/
    function supplyToken(
        uint8 _poolIndex,
        uint8 _leverageRate,
        uint256 _amountToSupply
    )
        external
        onlyRegisteredAccount
        onlySupportedPool(_poolIndex)
        onlySupportedLeverageRate(_leverageRate)
        noReentrant
        returns (uint)
    {
        // If user tries to supply zero amount, should revert
        if (_amountToSupply == 0) revert InvalidSupplyAmount();

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];

        // If user hasn't enough balance, should revert
        if (IERC20(pool.tokenAddress).balanceOf(msg.sender) < _amountToSupply)
            revert InsufficientUserBalance();

        if (getHealthRatio(msg.sender) < 100) revert InsufficientCollateral();

        address cTokenAddress;
        uint256 depositAmount;

        {
            // Calculate's leverage amount based on user's deposit amount
            uint256 leverageAmount = _amountToSupply.mul(_leverageRate);

            // If pool hasn't enough balance, should revert
            if (pool.balanceAmount < leverageAmount)
                revert InsufficientPoolBalance();

            // Calculates deposit amount based on leverage amount and user's deposit amount
            depositAmount = _amountToSupply + leverageAmount;

            // Transfer tokens from sender to this contract (Diamond proxy)
            IERC20(pool.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amountToSupply
            );

            LibFarmStorage.Deposit storage deposit = fs.deposits[msg.sender][
                _poolIndex
            ];

            cTokenAddress = pool.cTokenAddress;

            // Update pool's balance and borrow amount
            pool.balanceAmount -= leverageAmount;
            pool.borrowAmount += leverageAmount;

            // Store the current CToken exchange rate
            deposit.exchangeRate = CErc20(cTokenAddress).exchangeRateCurrent();

            // Update deposit's deposit and debt amount
            deposit.depositAmount[cTokenAddress] += _amountToSupply;
            deposit.debtAmount[cTokenAddress] += leverageAmount;
        }

        // Approve transfer on the ERC20 contract
        IERC20(pool.tokenAddress).safeApprove(cTokenAddress, depositAmount);

        uint256 balanceBeforeMint;
        uint256 balanceDiff;
        uint mintResult;

        {
            // Create a reference to the corresponding cToken contract, like cUSDC, cUSDT
            CErc20 cToken = CErc20(cTokenAddress);

            // Get the CToken balance before mint
            balanceBeforeMint = cToken.balanceOf(address(this));

            // Mint cTokens
            mintResult = cToken.mint(depositAmount);

            // Get the minted amount based on the current balance and the previous one
            balanceDiff = cToken.balanceOf(address(this)) - balanceBeforeMint;
        }

        {
            LibFarmStorage.Deposit storage deposit = fs.deposits[msg.sender][
                _poolIndex
            ];

            // Update deposit's stake amount
            deposit.stakeAmount[cTokenAddress] += balanceDiff;
        }

        // Update pool's stake amount
        pool.stakeAmount[cTokenAddress] += balanceDiff;

        emit TokenSupplied(mintResult, depositAmount);

        return mintResult;
    }

    /**
    @dev Allows a registered account to redeem cTokens from Compound and receive the underlying asset in return.
    @param _poolIndex The index of the pool to redeem cTokens from.
    @param _amount The amount of cTokens to redeem.
    @param redeemType The type of redeem operation to perform. If true, redeem by cToken amount. If false, redeem by underlying asset amount.
    **/
    function redeemCErc20Tokens(
        uint8 _poolIndex,
        uint256 _amount,
        bool redeemType
    )
        external
        onlyRegisteredAccount
        onlySupportedPool(_poolIndex)
        noReentrant
        returns (bool)
    {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        LibFarmStorage.Deposit storage deposit = fs.deposits[msg.sender][
            _poolIndex
        ];

        // If user's stake amount (CToken amount) hasn't enough for withdraw, should revert
        if (deposit.stakeAmount[pool.cTokenAddress] < _amount)
            revert InsufficientUserBalance();

        uint256 withdrawDepositAmount;

        {
            // If pool's CToken amount hasn't enough balance, should revert
            if (CErc20(pool.cTokenAddress).balanceOf(address(this)) < _amount)
                revert InsufficientPoolBalance();

            // Calculates deposit's total debt amount
            uint256 totalAmount = deposit.debtAmount[pool.cTokenAddress].add(
                deposit.depositAmount[pool.cTokenAddress]
            );

            // Calculate total token amount based on the current exchange rate
            uint256 withdrawAmount = _amount
                .mul(CErc20(pool.cTokenAddress).exchangeRateCurrent())
                .div(1e18);

            // Calculate user's token amount based on total amount and user's deposit amount
            withdrawDepositAmount = withdrawAmount
                .mul(deposit.depositAmount[pool.cTokenAddress])
                .div(totalAmount);

            // Update user's stake amount and deposit amount
            deposit.stakeAmount[pool.cTokenAddress] -= _amount;
            deposit.depositAmount[pool.cTokenAddress] -= withdrawDepositAmount;

            {
                // Calcualte user's debt amount based on total amount and user's debt amount
                uint256 withdrawDebtAmount = withdrawAmount
                    .mul(deposit.debtAmount[pool.cTokenAddress])
                    .div(totalAmount);

                // Update user's debt amount
                deposit.debtAmount[pool.cTokenAddress] -= withdrawDebtAmount;

                // Update pool's balance, borrow and stake amount
                pool.balanceAmount += withdrawDebtAmount;
                pool.borrowAmount -= withdrawDebtAmount;
                pool.stakeAmount[pool.cTokenAddress] -= _amount;
            }

            {
                // Calculate total reward based on the current change rate
                uint256 totalRewardAmount = withdrawAmount.sub(
                    _amount.mul(deposit.exchangeRate).div(1e18)
                );

                if (totalRewardAmount > 0) {
                    // Calculate user's total reward
                    uint256 lpReward = totalRewardAmount
                        .mul(fs.interestRate)
                        .div(100);

                    // Update Liquidity provider's reward
                    pool.balanceAmount += lpReward;

                    // Update deposit's reward (reward - lpreward);
                    deposit.rewardAmount += totalRewardAmount.sub(lpReward);
                }
            }
        }

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve user's asset based on a cToken amount
            redeemResult = CErc20(pool.cTokenAddress).redeem(_amount);
        } else {
            // Retrieve user's asset based on an amount of the asset
            redeemResult = CErc20(pool.cTokenAddress).redeemUnderlying(_amount);
        }

        // Send tokens to user
        IERC20(pool.tokenAddress).safeApprove(
            msg.sender,
            withdrawDepositAmount
        );
        IERC20(pool.tokenAddress).safeTransfer(
            msg.sender,
            withdrawDepositAmount
        );

        emit RedeemFinished(redeemResult, _amount);

        return true;
    }
}
