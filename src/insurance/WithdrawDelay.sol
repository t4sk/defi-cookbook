// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {IStake} from "./IStake.sol";

contract WithdrawQueue {
    // TODO: events
    // TODO: gas golf
    using SafeTransfer for IERC20;

    IERC20 public immutable token;
    IStake public immutable stake;

    struct Lock {
        uint256 amt;
        uint256 exp;
    }

    mapping(address usr => uint256) public counts;
    mapping(address usr => mapping(uint256 count => Lock)) public locks;

    uint256 public constant EPOCH = 3 days;
    // Last updated epoch
    uint256 public last;
    // Last 2 epoch to total amount locked
    uint256[2] public buckets;

    constructor(address _stake) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        token.approve(_stake, type(uint256).max);
        last = (block.timestamp / EPOCH) * EPOCH;
    }

    function queue(uint256 amt) external {
        stake.withdraw(msg.sender, address(this), amt);

        // Current epoch
        uint256 curr = (block.timestamp / EPOCH) * EPOCH;
        // End of next epoch
        uint256 exp = curr + 2 * EPOCH;

        if (last + 2 * EPOCH <= curr) {
            buckets[0] = 0;
            buckets[1] = 0;
        } else if (last + EPOCH == curr) {
            buckets[0] = buckets[1];
            buckets[1] = 0;
        }

        buckets[1] += amt;
        last = curr;

        locks[msg.sender][counts[msg.sender]] = Lock({amt: amt, exp: exp});
        counts[msg.sender] += 1;
    }

    function unlock(uint256 i) external {
        require(i < counts[msg.sender], "index out of bound");

        Lock storage lock = locks[msg.sender][i];
        require(lock.amt > 0, "lock amt = 0");
        require(lock.exp <= block.timestamp, "lock not expired");

        uint256 amt = lock.amt;
        delete locks[msg.sender][i];

        token.safeTransfer(msg.sender, amt);
    }

    function locked() public view returns (uint256) {
        uint256 curr = (block.timestamp / EPOCH) * EPOCH;

        if (last + 2 * EPOCH <= curr) {
            return 0;
        } else if (last + EPOCH == curr) {
            return buckets[1];
        }
        return buckets[0] + buckets[1];
    }
}
