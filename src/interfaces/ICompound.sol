// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface CErc20 {
    function mint(uint256) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint) external returns (uint);

    function redeemUnderlying(uint) external returns (uint);

    function balanceOf(address) external returns (uint256);

    function borrow(uint256) external returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);
}

interface CEth {
    function mint() external payable;

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint) external returns (uint);

    function redeemUnderlying(uint) external returns (uint);
}

interface Comptroller {
    function markets(address) external returns (bool, uint256);

    function enterMarkets(
        address[] calldata
    ) external returns (uint256[] memory);

    function getAccountLiquidity(
        address
    ) external view returns (uint256, uint256, uint256);
}
