// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/**
 * @title Math library
 * @notice The math library.
 * @author Alpha
 **/

library Math {
    uint256 internal constant DECIMAL_18 = 1e18;
    uint256 internal constant DECIMAL_6 = 1e6;
    uint256 internal constant DECIMAL_8 = 1e8;

    /**
     * @notice a ceiling division
     * @return the ceiling result of division
     */
    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "divider must more than 0");
        uint256 c = a / b;
        if (a % b != 0) {
            c = c + 1;
        }
        return c;
    }

    function toE18(uint256 _amount) internal pure returns (uint256) {
        return _amount * DECIMAL_18;
    }

    function toE6(uint256 _amount) internal pure returns (uint256) {
        return _amount * DECIMAL_6;
    }

    function toE8(uint256 _amount) internal pure returns (uint256) {
        return _amount * DECIMAL_8;
    }
}
