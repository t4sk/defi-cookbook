// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Math, RAY} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";

contract Rebase is Auth {
    uint256 public acc;
    uint256 public rate;
    uint256 public last;
    // Total shares
    uint256 public total;
    // User => shares
    mapping(address => uint256) public shares;
    // User => normalized balances
    mapping(address => uint256) public bals;

    constructor() {
        acc = RAY;
        rate = RAY;
        last = block.timestamp;
    }

    function calc() public view returns (uint256) {
        return acc * Math.rpow(rate, block.timestamp - last) / RAY;
    }

    function balance(address usr) external view returns (uint256) {
        return bals[usr] * calc() / RAY;
    }

    function sync(address usr) public {
        uint256 a = calc();
        acc = a;
        last = block.timestamp;
        if (usr != address(0)) {
            bals[usr] *= a / RAY;
        }
    }

    function set(uint256 r) external auth {
        require(r >= RAY, "r < 1");
        require(last == block.timestamp, "not synced");
        rate = r;
    }

    function mint(address usr, uint256 amt) external auth {
        require(last == block.timestamp, "not synced");
        total += amt;
        shares[usr] += amt;
        bals[usr] += amt * RAY / acc;
    }

    function burn(address usr, uint256 amt) external auth {
        require(last == block.timestamp, "not synced");
        // burn all -> amt = bals[usr] * acc / RAY
        total -= amt;
        shares[usr] -= amt;
        bals[usr] -= amt * RAY / acc;
    }
}
