// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

library Math {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }
}
