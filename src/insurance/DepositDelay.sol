// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {IStake} from "./lib/IStake.sol";
import {Auth} from "./lib/Auth.sol";

// TODO: events
// TODO: gas golf
contract DepositDelay is Auth {
    using SafeTransfer for IERC20;

    IERC20 public immutable token;
    IStake public immutable stake;
    uint256 public immutable DELAY;

    struct Lock {
        uint256 amt;
        uint256 exp;
    }

    // user => number of locks
    mapping(address usr => uint256 count) public counts;
    // user => lock index => lock
    mapping(address usr => mapping(uint256 i => Lock)) public locks;
    // Total amount locked
    uint256 public keep;

    constructor(address _stake, uint256 _delay) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        token.approve(address(stake), type(uint256).max);
        DELAY = _delay;
    }

    function queue(uint256 amt) external returns (uint256) {
        // If stake.exp < lock.exp, then call cancel
        require(!stake.stopped(), "stopped");

        token.safeTransferFrom(msg.sender, address(this), amt);
        keep += amt;

        uint256 i = counts[msg.sender];
        locks[msg.sender][i] = Lock({amt: amt, exp: block.timestamp + DELAY});
        counts[msg.sender] = i + 1;

        return i;
    }

    function deposit(uint256 i) external {
        Lock storage lock = locks[msg.sender][i];
        require(lock.amt > 0, "lock amt = 0");
        require(lock.exp <= block.timestamp, "lock not expired");

        uint256 amt = lock.amt;
        keep -= amt;
        delete locks[msg.sender][i];

        stake.deposit(msg.sender, amt);
    }

    function cancel(uint256 i) external {
        Lock storage lock = locks[msg.sender][i];
        uint256 amt = lock.amt;
        require(amt > 0, "lock amt = 0");

        delete locks[msg.sender][i];
        token.safeTransfer(msg.sender, amt);
    }

    function recover(address _token) external auth {
        if (_token == address(0)) {
            (bool ok,) = msg.sender.call{value: address(this).balance}("");
            require(ok, "send ETH failed");
        } else if (_token == address(token)) {
            uint256 bal = token.balanceOf(address(this));
            token.safeTransfer(msg.sender, bal - keep);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, bal);
        }
    }
}
