// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math} from "../lib/Math.sol";

contract Stake {
    using SafeTransfer for IERC20;

    // TODO: events

    IERC20 public immutable token;

    bool public stopped;
    mapping(address => bool) public auths;

    // Last updated timestamp
    uint256 public up;
    // Expiration
    uint256 public exp;
    // Rate per second
    uint256 public rate;
    // Rate accumulator
    uint256 public acc;

    modifier auth() {
        require(auths[msg.sender], "not auth");
        _;
    }

    modifier live() {
        require(!stopped, "stopped");
        _;
    }

    modifier paused() {
        require(stopped, "not stopped");
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        // TODO:emit
        auths[msg.sender] = true;
        updatedAt = block.timestamp;
        expAt = block.timestamp;
    }

    function allow(address usr) external auth {
        auths[usr] = true;
    }

    function deny(address usr) external auth {
        auths[usr] = false;
    }

    function deposit() external auth live {
        // queue -> delay -> deposit
        // not stopped
    }

    function withdraw() external auth live {
        // queue -> delay -> withdraw
        // not stopped
    }

    function drip() public {
        uint256 dt = block.timestamp - up;
    }

    // TODO: auth?
    function pay() external {}

    // TODO
    // function extend() external {}

    function cut() external auth paused {
        // TODO: stopped?
        // delete withdrawal queue + pull funds from withdrawal queue
    }

    // Insurer - stakers
    // get rewards

    // restake (get rewards + deposit (skip withdrawal queue))

    // TODO: emergency clean up

    function go() external auth paused {
        stopped = false;
    }

    function stop() external auth live {
        stopped = true;
    }
}
