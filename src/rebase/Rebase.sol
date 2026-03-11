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

    constructor() {
        acc = RAY;
        rate = RAY;
        last = block.timestamp;
    }

    function set(uint256 r) external auth {
        require(r >= RAY, "r < 1");
        require(last == block.timestamp, "not synced");
        rate = r;
    }

    function calc() public view returns (uint256) {
        return acc * Math.rpow(rate, block.timestamp - last) / RAY;
    }

    function balance(address usr) external view returns (uint256) {
        return shares[usr] * calc() / RAY;
    }

    function sync() external {
        acc = calc();
        last = block.timestamp;
    }

    function join(address usr, uint256 amt) external auth returns (uint256) {
        require(last == block.timestamp, "not synced");
        uint256 s = amt * RAY / acc;
        total += s;
        shares[usr] += s;
        return s;
    }

    function exit(address usr, uint256 amt) external auth returns (uint256) {
        require(last == block.timestamp, "not synced");
        uint256 s = amt * RAY / acc;
        total -= s;
        shares[usr] -= s;
        // burn all -> amt = shares[usr] * acc / RAY
        return s;
    }
}
