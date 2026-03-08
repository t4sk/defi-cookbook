// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {IStake} from "./lib/IStake.sol";
import {Auth} from "./lib/Auth.sol";

contract WithdrawDelay is Auth {
    using SafeTransfer for IERC20;

    event Queue(address indexed usr, uint256 i, uint256 amt);
    event Unlock(address indexed usr, uint256 i, uint256 amt);
    event Dump(uint256 amt);

    IERC20 public immutable token;
    IStake public immutable stake;
    // Duration of an epoch
    uint256 public immutable EPOCH;

    struct Lock {
        uint256 amt;
        uint256 exp;
    }

    // User => lock count
    mapping(address usr => uint256 count) public counts;
    // User => lock index => Lock
    mapping(address usr => mapping(uint256 i => Lock)) public locks;
    // Total amount queued
    uint256 public keep;

    // Last updated epoch
    uint256 public last;
    // Total queued amounts in the last 2 epoch
    uint256[2] public buckets;
    // Total amount dumped
    uint256 public dumped;
    bool public stopped;

    constructor(address _stake, uint256 _epoch) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        EPOCH = _epoch;
        last = (block.timestamp / EPOCH) * EPOCH;
    }

    function queue(uint256 amt) external returns (uint256) {
        require(!stopped, "stopped");

        stake.withdraw(msg.sender, address(this), amt);
        keep += amt;

        // Current epoch
        uint256 curr = (block.timestamp / EPOCH) * EPOCH;
        // End of next epoch
        uint256 exp = curr + 2 * EPOCH;

        // Update buckets
        if (last + 2 * EPOCH <= curr) {
            buckets[0] = 0;
            buckets[1] = 0;
        } else if (last + EPOCH == curr) {
            buckets[0] = buckets[1];
            buckets[1] = 0;
        }

        buckets[1] += amt;
        last = curr;

        uint256 i = counts[msg.sender];
        locks[msg.sender][i] = Lock({amt: amt, exp: exp});
        counts[msg.sender] = i + 1;

        emit Queue(msg.sender, i, amt);

        return i;
    }

    function unlock(uint256 i) external {
        require(i < counts[msg.sender], "index out of bound");

        Lock storage lock = locks[msg.sender][i];
        require(lock.amt > 0, "lock amt = 0");
        require(lock.exp <= block.timestamp, "lock not expired");
        if (stopped) {
            // Lock expired before dump, dump = 0 or refill was called
            require(lock.exp <= last || dumped == 0, "dumped");
        }

        uint256 amt = lock.amt;
        keep -= amt;
        delete locks[msg.sender][i];

        token.safeTransfer(msg.sender, amt);

        emit Unlock(msg.sender, i, amt);
    }

    function dump() external auth returns (uint256 amt) {
        require(!stopped, "stopped");
        stopped = true;

        uint256 curr = (block.timestamp / EPOCH) * EPOCH;

        if (last + 2 * EPOCH <= curr) {
            buckets[0] = 0;
            buckets[1] = 0;
        } else if (last + EPOCH == curr) {
            buckets[0] = buckets[1];
            buckets[1] = 0;
        }

        last = curr;
        amt = buckets[0] + buckets[1];

        if (amt > 0) {
            buckets[0] = 0;
            buckets[1] = 0;
            dumped = amt;
        }

        stake.stop();

        emit Dump(amt);
    }

    function cover(address dst) external auth {
        require(stopped, "not stopped");
        require(stake.state() == IStake.State.Cover, "invalid state");
        uint256 amt = dumped;
        keep -= amt;
        dumped = 0;
        if (amt > 0) {
            token.approve(address(stake), amt);
        }
        stake.cover(dst, amt);
    }

    function refill() external auth {
        require(stopped, "not stopped");
        require(stake.state() == IStake.State.Exit, "invalid state");
        dumped = 0;
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
