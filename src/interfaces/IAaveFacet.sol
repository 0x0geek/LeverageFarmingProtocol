// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

interface IAaveFacet {

    function withdrawFromAave(uint8 _poolIndex, uint256 _amount) external;
}
