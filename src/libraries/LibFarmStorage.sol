// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

library LibFarmStorage {
    bytes32 constant STORAGE_POSITION =
        keccak256("diamond.leveragefarming.farm.storage");

    address public constant ETHER_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT_ADDRESS =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address public constant CUSDC_ADDRESS =
        0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant CUSDT_ADDRESS =
        0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address public constant CETHER_ADDRESS =
        0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    address public constant AUSDC_ADDRESS =
        0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address public constant AUSDT_ADDRESS =
        0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address public constant AETHER_ADDRESS =
        0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;

    address internal constant AAVE_POOL_LP_TOKEN_ADDRESS =
        0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900;

    address internal constant CRV_TOKEN_ADDRESS =
        0xD533a949740bb3306d119CC777fa900bA034cd52;

    uint256 internal constant USDC_DECIMAL = 1e6;

    uint256 public constant MAX_LEVERAGE_LEVEL = 5;
    uint8 public constant COLLATERAL_FACTOR = 83;
    uint8 public constant MAX_POOL_LENGTH = 3;
    uint8 public constant LIQUIDATE_FEE = 110;

    struct Pool {
        address tokenAddress;
        address cTokenAddress;
        address aTokenAddress;
        address crvLpTokenAddress;
        uint256 balanceAmount;
        uint256 interestAmount;
        uint256 borrowAmount;
        mapping(address => uint256) stakeAmount;
        uint256 assetAmount;
        uint256 rewardAmount;
        bool supported;
    }

    struct Deposit {
        uint256 amount;
        uint256 assetAmount;
        uint256 rewardAmount;
        uint256 exchangeRate;
        mapping(address => uint256) depositAmount;
        mapping(address => uint256) debtAmount;
        mapping(address => uint256) stakeAmount;
    }

    struct FarmStorage {
        bool initialized;
        mapping(uint8 => Pool) pools;
        mapping(address => bool) accounts;
        mapping(address => mapping(uint8 => Deposit)) deposits;
        uint8 interestRate;
        uint8 collateralFactor;
        address owner;
    }

    function farmStorage() internal pure returns (FarmStorage storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
