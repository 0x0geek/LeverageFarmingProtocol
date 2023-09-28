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
        if (tokenAddr == address(0)) {} else {
            if (IERC20(tokenAddr).balanceOf(msg.sender) < _amount)
                revert InsufficientUserBalance();
            IERC20(tokenAddr).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }
        uint256 assetAmount = calculateAssetAmount(_poolIndex, _amount);
        pool.assetAmount += assetAmount;
        pool.balanceAmount += _amount;
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];
        depositor.amount += _amount;
        depositor.assetAmount += assetAmount;
        emit Deposit(msg.sender, _poolIndex, _amount);
    }

    function liquidate(
        address _user,
        uint8 _poolIndex,
        uint256 _amount
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
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

        uint256 healthRatio = (depositor.amount +
            getUserDebt(_user, token, _poolIndex))
            .div(depositor.debtAmount[token])
            .mul(LibFarmStorage.COLLATERAL_FACTOR);

        if (healthRatio >= 100) revert InvalidLiquidate();

        if (_amount < depositor.debtAmount[token])
            revert InsufficientLiquidateAmount();

        IERC20(pool.tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 liquidatePortion = depositor
            .stakeAmount[token]
            .mul(LibFarmStorage.LIQUIDATE_FEE)
            .div(100);

        liquidator.stakeAmount[token] += liquidatePortion;
        depositor.stakeAmount[token] -= liquidatePortion;
        depositor.debtAmount[token] -= _amount;
    }

    function withdraw(
        uint8 _poolIndex,
        uint256 _amount
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];
        uint256 assetAmount = depositor.assetAmount;
        // check if User has sufficient withdraw amount
        if (assetAmount == 0) revert ZeroAmountForWithdraw();
        uint256 amount = calculateAmount(_poolIndex, assetAmount);
        LibFarmStorage.Pool memory pool = fs.pools[_poolIndex];
        if (amount > pool.balanceAmount) revert NotAvailableForWithdraw();
        depositor.assetAmount -= assetAmount;
        pool.balanceAmount -= amount;
        pool.assetAmount -= assetAmount;
        IERC20(pool.tokenAddress).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, _poolIndex, _amount);
    }

    function claimReward(
        uint8 _poolIndex
    ) external onlyRegisteredAccount onlySupportedPool(_poolIndex) noReentrant {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            msg.sender
        ];

        if (depositor.rewardAmount == 0) revert NoReward();

        IERC20 token = IERC20(pool.tokenAddress);
        token.safeApprove(msg.sender, depositor.rewardAmount);
        token.safeTransfer(msg.sender, depositor.rewardAmount);

        emit ClaimReward(msg.sender, depositor.rewardAmount);
    }
}
