// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math, RAY} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";

interface IMint is IERC20 {
    function mint(address dst, uint256 amt) external;
}

contract Rebase is Auth {
    using SafeTransfer for IMint;

    IMint public immutable token;
    uint256 public acc;
    uint256 public rate;
    uint256 public last;
    // Total shares
    uint256 public total;
    // User => shares
    mapping(address => uint256) public shares;

    constructor(address _token) {
        token = IMint(_token);
        acc = RAY;
        rate = RAY;
        last = block.timestamp;
    }

    function set(uint256 r) external auth {
        require(r >= RAY, "r < 1");
        sync();
        rate = r;
    }

    function calc() public view returns (uint256) {
        return acc * Math.rpow(rate, block.timestamp - last) / RAY;
    }

    function sync() public returns (uint256 amt) {
        if (block.timestamp > last) {
            uint256 a0 = acc;
            uint256 a1 = calc();
            acc = a1;
            last = block.timestamp;
            amt = (a1 - a0) * total / RAY;
            if (amt > 0) {
                token.mint(address(this), amt);
            }
        }
    }

    function balance(address usr) external view returns (uint256) {
        return shares[usr] * calc() / RAY;
    }

    function join(uint256 amt) external returns (uint256) {
        sync();
        token.transferFrom(msg.sender, address(this), amt);
        uint256 s = amt * RAY / acc;
        require(s > 0, "s = 0");
        total += s;
        shares[msg.sender] += s;
        return s;
    }

    function exit(uint256 s) external returns (uint256) {
        sync();
        total -= s;
        shares[msg.sender] -= s;
        uint256 amt = s * acc / RAY;
        require(amt > 0, "amt = 0");
        token.transfer(msg.sender, amt);
        return amt;
    }

    function transfer(address dst, uint256 s) external {
        shares[msg.sender] -= s;
        shares[dst] += s;
    }
}
