// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math} from "../lib/Math.sol";

interface IStake {
    function token() external view returns (address);
    function stopped() external view returns (bool);
    function deposit(address usr, uint256 amt) external;
    function withdraw(address usr, address dst, uint256 amt) external;
    function getRewards(address usr) external returns (uint256 amt);
}

contract WithdrawQueue {
    // TODO: events
    using SafeTransfer for IERC20;

    IERC20 public immutable token;
    IStake public immutable stake;
    uint256 public immutable delay;

    struct Lock {
        uint256 amt;
        uint256 exp;
    }

    mapping(address usr => uint256) public counts;
    mapping(address usr => mapping(uint256 count => Lock)) public locks;

    constructor(address _stake, uint256 _delay) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        delay = _delay;
    }

    function queue(uint256 amt) external {
        stake.withdraw(msg.sender, address(this), amt);
        locks[msg.sender][counts[msg.sender]] =
            Lock({amt: amt, exp: block.timestamp + delay});
        counts[msg.sender] += 1;
    }

    function unlock(uint256 i) external {
        require(i < counts[msg.sender], "index out of bound");

        Lock storage lock = locks[msg.sender][i];
        require(lock.amt > 0, "lock amt = 0");
        require(lock.exp <= block.timestamp, "lock not expired");

        uint256 amt = lock.amt;
        lock.amt = 0;

        token.safeTransfer(msg.sender, amt);
    }
}
