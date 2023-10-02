// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "../interfaces/ICompoundFacet.sol";
import "../interfaces/IAaveFacet.sol";
import "../interfaces/ICurveFacet.sol";
import "../libraries/ReEntrancyGuard.sol";
import "../libraries/LibFarmStorage.sol";

import "./BaseFacet.sol";

contract AccountFacet is BaseFacet, ReEntrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using LibMath for uint256;

    event Deposit(address indexed _user, uint8 _poolIndex, uint256 _amount);
    event Repay(address indexed _user, address indexed _token, uint256 _amount);
    event Withdraw(address indexed _user, uint8 _poolIndex, uint256 _amount);
    event ClaimReward(address indexed _user, uint256 _amount);

    /**
    @dev Allows a registered account to deposit tokens into a supported pool.
    @param _poolIndex The index of the pool to deposit into.
    @param _amount The amount of tokens to deposit.
    */
    function deposit(
        uint8 _poolIndex,
        uint256 _amount
    )
        external
        onlyRegisteredAccount
        onlySupportedPool(_poolIndex)
        onlyAmountNotZero(_amount)
        noReentrant
    {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        address tokenAddr = pool.tokenAddress;

        // If user hasn't sufficient balance, should revert
        if (IERC20(tokenAddr).balanceOf(msg.sender) < _amount)
            revert InsufficientUserBalance();

        // Transfer tokens to diamond proxy
        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), _amount);

        // Calculate asset amount based on the deposit amount
        uint256 assetAmount = calculateAssetAmount(_poolIndex, _amount);

        // Calculate pool asset and balance amount
        pool.assetAmount += assetAmount;
        pool.balanceAmount += _amount;

        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        // Calculate depositor's asset and balance amount
        depositor.amount += _amount;
        depositor.assetAmount += assetAmount;
        emit Deposit(msg.sender, _poolIndex, _amount);
    }

    /**
    @dev Allows a registered account to liquidate another account's debt in a supported pool.
    @param _user The address of the account to be liquidated.
    @param _poolIndex The index of the pool to liquidate in.
    @param _amount The amount of tokens to use for liquidation.
    **/
    function liquidate(
        address _user,
        uint8 _poolIndex,
        uint256 _amount
    ) external onlySupportedPool(_poolIndex) noReentrant {
        // User can't liquidate his one.
        if (_user == msg.sender) revert InvalidLiquidateUser();

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            _user
        ];
        LibFarmStorage.Depositor storage liquidator = fs.depositors[_poolIndex][
            msg.sender
        ];
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];

        address token = pool.tokenAddress;

        // Calculate user's health ratio
        uint256 healthRatio = (depositor.amount +
            getUserDebt(_user, token, _poolIndex))
            .div(depositor.debtAmount[token])
            .mul(LibFarmStorage.COLLATERAL_FACTOR);

        // If health ratio is greater than 1, shouldn't be liquidated
        if (healthRatio >= 100) revert InvalidLiquidate();

        // If liquidator hasn't sufficient balance, should revert
        if (_amount < depositor.debtAmount[token])
            revert InsufficientLiquidateAmount();

        // Transfer tokens to diamond proxy for liquidattion
        IERC20(pool.tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Calculate liquidator's portion
        uint256 liquidatePortion = depositor
            .stakeAmount[token]
            .mul(LibFarmStorage.LIQUIDATE_FEE)
            .div(100);

        // Update liquidator's portion
        liquidator.stakeAmount[token] += liquidatePortion;
        depositor.stakeAmount[token] -= liquidatePortion;
        depositor.debtAmount[token] -= _amount;
    }

    /**
    @dev Allows a registered account to withdraw their assets from a supported pool.
    @param _poolIndex The index of the pool to withdraw from.
    @param _amount The amount of tokens to withdraw.
    **/
    function withdraw(
        uint8 _poolIndex,
        uint256 _amount
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        // get depositor's asset amount
        uint256 assetAmount = depositor.assetAmount;

        // check if User has sufficient withdraw amount
        if (assetAmount == 0) revert ZeroAmountForWithdraw();

        // calculate user's amount based on his asset amount
        uint256 amount = calculateAmount(_poolIndex, assetAmount);
        LibFarmStorage.Pool memory pool = fs.pools[_poolIndex];

        // If pool hasnt sufficient balance for withdraw, should revert
        if (amount > pool.balanceAmount) revert NotAvailableForWithdraw();

        // Update depositor's asset and pool's balance and asset amount
        depositor.assetAmount -= assetAmount;
        pool.balanceAmount -= amount;
        pool.assetAmount -= assetAmount;

        // Transfer tokens to user
        IERC20(pool.tokenAddress).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, _poolIndex, _amount);
    }

    /**
    @dev Allows a registered account to claim their reward for a specific pool.
    @param _poolIndex The index of the pool to claim the reward from.
    **/
    function claimReward(
        uint8 _poolIndex
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        // If user hasn't reward, should revert
        if (depositor.rewardAmount == 0) revert NoReward();

        // Update depositor's reward amount
        depositor.rewardAmount = 0;

        // Transfer reward to depositor
        IERC20 token = IERC20(pool.tokenAddress);
        token.safeApprove(msg.sender, depositor.rewardAmount);
        token.safeTransfer(msg.sender, depositor.rewardAmount);

        emit ClaimReward(msg.sender, depositor.rewardAmount);
    }
}
