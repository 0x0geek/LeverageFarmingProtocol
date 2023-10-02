// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

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

    modifier onlySupportedToken(address _token) {
        checkIfSupportedToken(_token);
        _;
    }

    modifier onlySupportedAToken(address _token) {
        checkIfSupportedAToken(_token);
        _;
    }

    modifier onlySupportedCToken(address _token) {
        checkIfSupportedCToken(_token);
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

    function checkIfSupportedToken(
        address _tokenAddress
    ) internal view virtual {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (
            fs.pools[0].tokenAddress == _tokenAddress ||
            fs.pools[1].tokenAddress == _tokenAddress ||
            fs.pools[2].tokenAddress == _tokenAddress
        ) return;

        revert NotSupportedToken();
    }

    function checkIfSupportedAToken(
        address _tokenAddress
    ) internal view virtual {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (
            fs.pools[0].aTokenAddress == _tokenAddress ||
            fs.pools[1].aTokenAddress == _tokenAddress ||
            fs.pools[2].aTokenAddress == _tokenAddress
        ) return;

        revert NotSupportedToken();
    }

    function checkIfSupportedCToken(
        address _tokenAddress
    ) internal view virtual {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();

        if (
            fs.pools[0].cTokenAddress == _tokenAddress ||
            fs.pools[1].cTokenAddress == _tokenAddress ||
            fs.pools[2].cTokenAddress == _tokenAddress
        ) return;

        revert NotSupportedToken();
    }

    function calculateAssetAmount(
        uint8 _poolIndex,
        uint256 _amount
    ) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Pool memory pool = fs.pools[_poolIndex];

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
        LibFarmStorage.Pool memory pool = fs.pools[_poolIndex];

        uint256 totalLiquidityAmount = pool
            .borrowAmount
            .add(pool.balanceAmount)
            .add(pool.rewardAmount);

        uint256 amount = _assetAmount.mul(totalLiquidityAmount).divCeil(
            pool.assetAmount
        );

        return amount;
    }

    function getUserDebt(
        address _user,
        address _token,
        uint8 _poolIndex
    ) internal view returns (uint256) {
        LibFarmStorage.FarmStorage storage fs = LibFarmStorage.farmStorage();
        LibFarmStorage.Depositor storage depositor = fs.depositors[_poolIndex][
            _user
        ];

        uint256 userDebt = depositor.debtAmount[_token];

        userDebt +=
            depositor.stakeAmount[_token] *
            LibPriceOracle.getLatestPrice(_token);

        return userDebt;
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
}
