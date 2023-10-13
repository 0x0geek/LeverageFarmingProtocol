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

        LibFarmStorage.Deposit storage userDeposit = fs.deposits[msg.sender][
            _poolIndex
        ];

        // Calculate deposit's asset and balance amount
        userDeposit.amount += _amount;
        userDeposit.assetAmount += assetAmount;
        emit Deposit(msg.sender, _poolIndex, _amount);
    }

    /**
    @dev Allows a registered account to liquidate another account's debt in a supported pool.
    @param _user The address of the account to be liquidated.
    @param _amount The amount of tokens to use for liquidation.
    @param _collateral The address of token to use for liquidation.
    **/
    function liquidate(
        address _diamond,
        address _user,
        uint256 _amount,
        address _collateral
    )
        external
        payable
        onlySupportedCollateral(_collateral)
        onlyRegisteredUser(_user)
        noReentrant
    {
        // User can't liquidate his one.
        if (_user == msg.sender) revert InvalidLiquidateUser();

        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        // If health ratio is greater than 1, shouldn't be liquidated
        if (getHealthRatio(_user) >= 100) revert InvalidLiquidate();

        // If liquidator hasn't sufficient balance, should revert
        uint256 amount;

        if (_collateral == address(0x0)) {
            amount = (msg.value)
                .mul(
                    LibPriceOracle.getLatestPrice(LibFarmStorage.ETHER_ADDRESS)
                )
                .div(1e8);
        }

        uint256 liquidateAmount = getUserDebt(_user)
            .div(LibFarmStorage.LIQUIDATE_FEE)
            .mul(100);

        if (_collateral != address(0x0)) {
            // Transfer tokens to diamond proxy for liquidattion
            IERC20(_collateral).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        CurveData testCrvData = CurveData({
            poolAddress: AAVE_POOL_ADDRESS,
            gaugeAddress: AAVE_LIQUIDITY_GAUGE_ADDRESS,
            minterAddress: CRV_TOKEN_MINTER_ADDRESS,
            lpTokenAddress: AAVE_POOL_LP_TOKEN_ADDRESS
        });

        // Calculate liquidator's portion
        for (uint8 i; i != LibFarmStorage.MAX_POOL_LENGTH; ++i) {

            LibFarmStorage.Deposit storage liquidator = fs.deposits[msg.sender][
                i
            ];
            LibFarmStorage.Deposit storage userDeposit = fs.deposits[_user][i];
            LibFarmStorage.Pool storage pool = fs.pools[i];

            // Close user's portion
            IAaveFacet(_diamond).withdrawFromAave(i, userDeposit.stakeAmount[pool.aTokenAddress]);
            ICompoundFacet(_diamond).redeemCErc20Tokens(i, userDepost.stakeAmount[pool.cTokenAddress], true);
            ICurveFacet(_diamond).withdrawFromCurve(i, testCrvData, userDeposit.stakeAmount[pool.crvLpTokenAddress]);
        }
    }

    /**
    @dev Allows a registered account to withdraw their assets from a supported pool.
    @param _poolIndex The index of the pool to withdraw from.
    @param _assetAmount The amount of tokens to withdraw.
    **/
    function withdraw(
        uint8 _poolIndex,
        uint256 _assetAmount
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Deposit storage userDeposit = fs.deposits[msg.sender][
            _poolIndex
        ];

        // check if User has sufficient withdraw amount
        if (_assetAmount == 0) revert ZeroAmountForWithdraw();

        // calculate user's amount based on his asset amount
        uint256 amount = calculateAmount(_poolIndex, _assetAmount);
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];

        // If pool hasnt sufficient balance for withdraw, should revert
        if (amount > pool.balanceAmount) revert NotAvailableForWithdraw();

        // Update deposit's asset and pool's balance and asset amount
        userDeposit.assetAmount -= _assetAmount;
        pool.balanceAmount -= amount;
        pool.assetAmount -= _assetAmount;

        // Transfer tokens to user
        IERC20(pool.tokenAddress).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, _poolIndex, amount);
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
        LibFarmStorage.Deposit storage userDeposit = fs.deposits[msg.sender][
            _poolIndex
        ];

        // If user hasn't reward, should revert
        if (userDeposit.rewardAmount == 0) revert NoReward();

        // Update deposit's reward amount
        userDeposit.rewardAmount = 0;

        // Transfer reward to deposit
        IERC20 token = IERC20(pool.tokenAddress);
        token.safeApprove(msg.sender, userDeposit.rewardAmount);
        token.safeTransfer(msg.sender, userDeposit.rewardAmount);

        emit ClaimReward(msg.sender, userDeposit.rewardAmount);
    }
}
