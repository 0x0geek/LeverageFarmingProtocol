// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "forge-std/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/LibFarmStorage.sol";
import "../libraries/ReEntrancyGuard.sol";
import "../libraries/LibPriceOracle.sol";
import "../libraries/LibMath.sol";

contract BaseFacet {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using LibMath for uint256;

    event Borrow(
        address indexed _user,
        address indexed _borrowToken,
        uint256 _borrowAmount
    );

    event WithdrawFromAave(address indexed, uint256);

    error InvalidAccount();
    error InvalidOwner();
    error AmountZero();
    error NotSupportedToken();
    error InsufficientUserBalance();
    error InsufficientCollateral();
    error InsufficientPoolBalance();
    error InsufficientBorrowBalance();
    error InsufficientCollateralBalance();
    error ZeroCollateralAmountForBorrow();
    error InvalidLiquidate();
    error InsufficientLiquidateAmount();
    error InvalidLiquidateUser();
    error AlreadyInitialized();
    error NotOnwer();
    error ZeroAmountForWithdraw();
    error NotAvailableForWithdraw();
    error InvalidDepositAmount();
    error InvalidSupplyAmount();
    error InvalidPool();
    error NoReward();
    error InvalidLeverageRate();

    modifier onlyRegisteredAccount() {
        checkExistAccount(msg.sender);
        _;
    }

    modifier onlyAdmin() {
        checkAdmin(msg.sender);
        _;
    }

    modifier onlyAmountNotZero(uint256 _amount) {
        checkIfAmountNotZero(_amount);
        _;
    }

    modifier onlySupportedPool(uint8 _poolIndex) {
        checkIfSupportedPool(_poolIndex);
        _;
    }

    modifier onlySupportedLeverageRate(uint8 _leverageRate) {
        checkIfSupportedLeverageRate(_leverageRate);
        _;
    }

    modifier onlySupportedCollateral(address _collateral) {
        checkIfSupportedCollateral(_collateral);
        _;
    }

    function checkExistAccount(address _sender) internal view {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        if (fs.accounts[_sender] == false) revert InvalidAccount();
    }

    function checkAdmin(address _sender) internal view {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (fs.owner != address(0) && fs.owner != _sender)
            revert InvalidOwner();
    }

    function checkIfAmountNotZero(uint256 _amount) internal view virtual {
        if (_amount == 0) revert AmountZero();
    }

    function checkIfSupportedPool(uint8 _poolIndex) internal view virtual {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (fs.pools[_poolIndex].supported == false) revert NotSupportedToken();
    }

    function checkIfSupportedCollateral(
        address _collateral
    ) internal view virtual {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (
            fs.pools[0].tokenAddress == _collateral ||
            fs.pools[1].tokenAddress == _collateral ||
            fs.pools[2].tokenAddress == _collateral
        ) return;

        revert NotSupportedToken();
    }

    function checkIfSupportedLeverageRate(
        uint8 _leverageRate
    ) internal view virtual {
        if (_leverageRate == 0 || _leverageRate > 5)
            revert InvalidLeverageRate();
    }

    function calculateAssetAmount(
        uint8 _poolIndex,
        uint256 _amount
    ) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];

        uint256 totalLiquidityAmount = pool
            .borrowAmount
            .add(pool.balanceAmount)
            .add(pool.rewardAmount);

        if (pool.assetAmount == 0 || totalLiquidityAmount == 0) return _amount;

        uint256 assetAmount = _amount.mul(pool.assetAmount).div(
            totalLiquidityAmount
        );

        return assetAmount;
    }

    function calculateAmount(
        uint8 _poolIndex,
        uint256 _assetAmount
    ) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool storage pool = fs.pools[_poolIndex];

        uint256 totalLiquidityAmount = pool
            .borrowAmount
            .add(pool.balanceAmount)
            .add(pool.rewardAmount);

        uint256 amount = _assetAmount.mul(totalLiquidityAmount).divCeil(
            pool.assetAmount
        );

        return amount;
    }

    function getUserPortionByPool(
        address _user,
        address _token,
        uint8 _poolIndex
    ) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Deposit storage deposit = fs.deposits[_user][_poolIndex];
        return deposit.debtAmount[_token];
    }

    function getUserDebtByPool(
        address _user,
        address _token,
        uint8 _poolIndex
    ) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Deposit storage deposit = fs.deposits[_user][_poolIndex];
        return deposit.debtAmount[_token];
    }

    function getPoolIndexFromToken(
        address _token
    ) internal view returns (uint8) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        for (uint8 i; i != LibFarmStorage.MAX_POOL_LENGTH; ++i) {
            if (fs.pools[i].tokenAddress == _token) return i;
        }

        return type(uint8).max;
    }

    function getPoolIndexFromCToken(
        address _cToken
    ) internal view returns (uint8) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        for (uint8 i; i != LibFarmStorage.MAX_POOL_LENGTH; ++i) {
            if (fs.pools[i].cTokenAddress == _cToken) return i;
        }

        return type(uint8).max;
    }

    function getPoolIndexFromAToken(
        address _aToken
    ) internal view returns (uint8) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        for (uint8 i; i != LibFarmStorage.MAX_POOL_LENGTH; ++i) {
            if (fs.pools[i].aTokenAddress == _aToken) return i;
        }

        return type(uint8).max;
    }

    function getHealthRatio(address _user) internal view returns (uint256) {
        uint256 totalUserPortion = getUserPortion(_user);
        uint256 totalUserDebt = getUserDebt(_user);

        uint256 healthRatio = totalUserPortion
            .mul(LibFarmStorage.COLLATERAL_FACTOR)
            .div(totalUserDebt);

        console.log("Health ratio");
        console.log(healthRatio);
        console.log(totalUserPortion);
        console.log(totalUserDebt);

        return 110;
    }

    function getUserDebt(address _user) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Deposit storage usdcDeposit = fs.deposits[_user][1];
        LibFarmStorage.Deposit storage usdtDeposit = fs.deposits[_user][2];

        uint256 userDebtAmount;

        for (uint8 i = 1; i != LibFarmStorage.MAX_POOL_LENGTH; ++i) {
            LibFarmStorage.Pool storage pool = fs.pools[i];
            userDebtAmount += getUserDebtByPool(_user, pool.aTokenAddress, i);
            userDebtAmount += getUserDebtByPool(_user, pool.cTokenAddress, i);
            userDebtAmount += getUserDebtByPool(
                _user,
                pool.crvLpTokenAddress,
                i
            );
        }

        return userDebtAmount;
    }

    function getUserPortion(address _user) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Deposit storage ethDeposit = fs.deposits[_user][1];
        LibFarmStorage.Deposit storage usdcDeposit = fs.deposits[_user][1];
        LibFarmStorage.Deposit storage usdtDeposit = fs.deposits[_user][2];

        uint256 etherUsdPrice = LibPriceOracle.getLatestPrice(
            LibPriceOracle.ETH_USD_PRICE_FEED
        );

        uint256 usdAmount;

        usdAmount += ethDeposit.amount.mul(etherUsdPrice).div(1e8);
        usdAmount += usdcDeposit.amount;
        usdAmount += usdtDeposit.amount;

        for (uint8 i = 1; i != LibFarmStorage.MAX_POOL_LENGTH; ++i) {
            LibFarmStorage.Pool storage pool = fs.pools[i];
            usdAmount += getUserPortionByPool(_user, pool.aTokenAddress, i);
            usdAmount += getUserPortionByPool(_user, pool.cTokenAddress, i);
            usdAmount += getUserPortionByPool(_user, pool.crvLpTokenAddress, i);
        }

        return usdAmount;
    }

    function getUserCollateralUsdValue(
        address _user
    ) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        uint256 totalUsdValue;

        uint256 etherUsdPrice = LibPriceOracle.getLatestPrice(
            LibPriceOracle.ETH_USD_PRICE_FEED
        );

        for (uint8 i; i != LibFarmStorage.MAX_POOL_LENGTH; ++i) {
            LibFarmStorage.Deposit storage deposit = fs.deposits[_user][i];
            if (i == 0) {
                if (deposit.amount > 0)
                    totalUsdValue += deposit.amount.mul(etherUsdPrice).div(1e8);
            } else {
                totalUsdValue += deposit.amount;
            }
        }

        return totalUsdValue;
    }

    function getBorrowableAmount(
        address _user,
        address _aggregatorAddress
    ) internal view returns (uint256) {
        uint256 totalUsdValue = getUserCollateralUsdValue(_user);
        uint256 tokenUsdPrice = LibPriceOracle.getLatestPrice(
            _aggregatorAddress
        );

        return totalUsdValue.div(tokenUsdPrice.div(1e2));
    }
}
