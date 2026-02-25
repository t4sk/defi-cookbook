// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {IStake} from "./lib/IStake.sol";

contract DepositDelay {
    using SafeTransfer for IERC20;

    IERC20 public immutable token;
    IStake public immutable stake;

    struct Lock {
        uint256 amt;
        uint256 exp;
    }

    uint256 public constant DELAY = 3 days;

    mapping(address usr => uint256) public counts;
    mapping(address usr => mapping(uint256 count => Lock)) public locks;

    constructor(address _stake) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        token.approve(address(stake), type(uint256).max);
    }

    function queue(uint256 amt) external {
        // TODO: require stake.exp > block.timestamp + DELAY?
        require(!stake.stopped(), "stopped");

        token.safeTransferFrom(msg.sender, address(this), amt);
        locks[msg.sender][counts[msg.sender]] =
            Lock({amt: amt, exp: block.timestamp + DELAY});
        counts[msg.sender] += 1;
    }

    function deposit(uint256 i) external {
        Lock storage lock = locks[msg.sender][i];
        require(lock.amt > 0, "lock amt = 0");
        require(lock.exp <= block.timestamp, "lock not expired");

        uint256 amt = lock.amt;
        delete locks[msg.sender][i];

        stake.deposit(msg.sender, amt);
    }

    function cancel(uint256 i) external {
        delete locks[msg.sender][i];
    }
}
