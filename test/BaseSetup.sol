// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {Utils} from "./utils/Util.sol";
import {IUniswapRouter} from "../src/interfaces/IUniswap.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseSetup is Test {
    address internal constant USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant UNISWAP_ROUTER_ADDRESS =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI_ADDRESS =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Skip forward block.timestamp for 3 days.
    uint256 internal constant SKIP_FORWARD_PERIOD = 3600 * 24 * 3;

    address[] internal pathUSDT;
    address[] internal pathUSDC;

    Utils internal utils;

    address payable[] internal users;
    address internal alice;
    address internal bob;

    IWETH internal weth;
    IERC20 internal usdc;
    IERC20 internal usdt;

    IUniswapRouter internal uniswapRouter;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(5);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");

        initPathForSwap();
        getStableCoinBalanceForTesting();
    }

    function initPathForSwap() internal {
        weth = IWETH(WETH_ADDRESS);
        usdc = IERC20(USDC_ADDRESS);
        usdt = IERC20(USDT_ADDRESS);

        pathUSDC = new address[](2);
        pathUSDC[0] = WETH_ADDRESS;
        pathUSDC[1] = USDC_ADDRESS;

        pathUSDT = new address[](2);
        pathUSDT[0] = WETH_ADDRESS;
        pathUSDT[1] = USDT_ADDRESS;
    }

    function swapETHToToken(
        address[] memory _path,
        address _to,
        uint256 _amount
    ) internal {
        uint256 deadline = block.timestamp + 3600000;

        uniswapRouter.swapExactETHForTokens{value: _amount}(
            0,
            _path,
            _to,
            deadline
        );
    }

    function getStableCoinBalanceForTesting() internal {
        uint wethAmount = 10 * 1e18;

        weth.approve(address(uniswapRouter), wethAmount * 10);

        uniswapRouter = IUniswapRouter(UNISWAP_ROUTER_ADDRESS);

        swapETHToToken(pathUSDC, address(alice), wethAmount);
        swapETHToToken(pathUSDT, address(alice), wethAmount);

        swapETHToToken(pathUSDC, address(bob), wethAmount);
        swapETHToToken(pathUSDT, address(bob), wethAmount);
    }
}
