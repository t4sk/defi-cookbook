// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Math, RAY} from "../lib/Math.sol";

contract Rebase {
    uint256 public acc;
    uint256 public rate;
    uint256 public last;

    constructor() {
        acc = RAY;
        rate = RAY;
        last = block.timestamp;
    }

    function calc() public view returns (uint256) {
        return acc * Math.rpow(rate, block.timestamp - last) / RAY;
    }

    function sync() public {
        acc = calc();
        last = block.timestamp;
    }

    function mint() public {}

    function burn() public {}
}
