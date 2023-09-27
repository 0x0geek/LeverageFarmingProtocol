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

    function depositToAave(
        address _tokenAddress,
        uint256 _amount
    )
        external
        onlyRegisteredAccount
        onlySupportedToken(_tokenAddress)
        noReentrant
    {
        if (_amount == 0) revert InvalidDepositAmount();

        IERC20 underlyingToken = IERC20(_tokenAddress);

        if (underlyingToken.balanceOf(msg.sender) < _amount)
            revert InsufficientUserBalance();

        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint8 poolIndex = getPoolIndexFromToken(_tokenAddress);

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[poolIndex];

        uint256 leverageAmount = _amount.mul(LibFarmStorage.LEVERAGE_LEVEL);
        uint256 depositAmount = _amount.add(leverageAmount);

        if (pool.balanceAmount < leverageAmount)
            revert InsufficientPoolBalance();

        LibFarmStorage.Depositor storage depositor = fs.depositors[poolIndex][
            msg.sender
        ];

        address aTokenAddress = pool.aTokenAddress;

        pool.balanceAmount -= leverageAmount;
        pool.borrowAmount += leverageAmount;

        depositor.depositAmount[aTokenAddress] += _amount;
        depositor.debtAmount[aTokenAddress] += leverageAmount;

        uint256 beforeATokenBalance = IERC20(aTokenAddress).balanceOf(
            address(this)
        );

        // Approve the Aave lending pool to spend the tokens
        underlyingToken.safeApprove(_lendingPool(), depositAmount);

        // Deposit tokens into Aave v2 lending pool
        ILendingPool(_lendingPool()).deposit(
            _tokenAddress,
            depositAmount,
            address(this),
            0
        );

        uint256 balanceDiff = IERC20(aTokenAddress)
            .balanceOf(address(this))
            .sub(beforeATokenBalance);

        depositor.stakeAmount[aTokenAddress] += balanceDiff;
        pool.stakeAmount += balanceDiff;
    }

    function withdrawFromAave(
        address _aTokenAddress,
        uint256 _amount
    )
        external
        onlyRegisteredAccount
        onlySupportedAToken(_aTokenAddress)
        noReentrant
    {
        uint8 poolIndex = getPoolIndexFromAToken(_aTokenAddress);

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[poolIndex];
        LibFarmStorage.Depositor storage depositor = fs.depositors[poolIndex][
            msg.sender
        ];

        if (depositor.stakeAmount[_aTokenAddress] < _amount)
            revert InsufficientUserBalance();

        IERC20 aToken = IERC20(_aTokenAddress);

        if (aToken.balanceOf(address(this)) < _amount)
            revert InsufficientPoolBalance();

        uint256 totalAmount = depositor.debtAmount[_aTokenAddress].add(
            depositor.depositAmount[_aTokenAddress]
        );

        uint256 withdrawDebtAmount = _amount
            .mul(depositor.debtAmount[_aTokenAddress])
            .div(totalAmount);

        depositor.stakeAmount[_aTokenAddress] -= _amount;
        depositor.depositAmount[_aTokenAddress] -= _amount
            .mul(depositor.depositAmount[_aTokenAddress])
            .div(totalAmount);

        uint256 totalRewardAmount = IERC20(_aTokenAddress).balanceOf(
            address(this)
        ) - pool.stakeAmount;
        uint256 rewardAmount = totalRewardAmount.mul(totalAmount).div(
            pool.stakeAmount
        );

        uint256 lpReward = rewardAmount.mul(fs.interestRate).div(100);

        pool.rewardAmount += lpReward;
        depositor.rewardAmount += rewardAmount.sub(lpReward);

        depositor.repayAmount[_aTokenAddress] += withdrawDebtAmount;

        pool.balanceAmount += withdrawDebtAmount;
        pool.borrowAmount -= withdrawDebtAmount;

        address lendingPoolAddr = _lendingPool();

        // Approve lending pool to spend your aTokens
        aToken.safeApprove(lendingPoolAddr, _amount);

        // Withdraw tokens from Aave v2 lending pool
        ILendingPool(lendingPoolAddr).withdraw(
            pool.tokenAddress,
            _amount,
            address(this)
        );

        uint256 tokenAmountForWithdraw = _amount.div(
            LibFarmStorage.LEVERAGE_LEVEL
        );

        IERC20(pool.tokenAddress).safeApprove(
            msg.sender,
            tokenAmountForWithdraw
        );
        IERC20(pool.tokenAddress).safeTransfer(
            msg.sender,
            tokenAmountForWithdraw
        );

        emit WithdrawFromAave(msg.sender, tokenAmountForWithdraw);
    }

    function _lendingPool() internal view returns (address) {
        return
            ILendingPoolAddressesProvider(AAVE_LENDING_POOL_ADDRESSES_PROVIDER)
                .getLendingPool();
    }
}
