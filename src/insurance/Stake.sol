// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "./lib/Auth.sol";

contract Stake is Auth {
    using SafeTransfer for IERC20;

    // TODO: events
    // TODO: gas golf
    // TODO: overflow dos?
    // TODO: handle rebase token (inf deposit + checking bal diff)?

    // Rate scale
    uint256 private constant R = 1e18;
    IERC20 public immutable token;

    bool public stopped;

    // Total staked
    uint256 public total;
    // user => staked amount
    mapping(address usr => uint256 amt) public shares;

    // Reward duration
    uint256 public immutable dur;
    // Last updated time
    uint256 public last;
    // Expiration time
    uint256 public exp;
    // Rate of token emission per second
    uint256 public rate;
    // Rate accumulator
    uint256 public acc;
    mapping(address usr => uint256 acc) public accs;
    // Total amount in rewards
    uint256 public keep;
    mapping(address usr => uint256 amt) public rewards;

    modifier live() {
        require(!stopped, "stopped");
        _;
    }

    constructor(address _token, uint256 _dur) {
        token = IERC20(_token);
        last = block.timestamp;
        exp = block.timestamp + _dur;
        dur = _dur;
    }

    function deposit(address usr, uint256 amt) external auth live {
        require(block.timestamp < exp, "expired");

        token.safeTransferFrom(msg.sender, address(this), amt);

        // TODO: restake
        sync(usr);
        total += amt;
        shares[usr] += amt;
    }

    function withdraw(address usr, address dst, uint256 amt) external live {
        if (block.timestamp < exp) {
            require(auths[msg.sender], "not auth");
        }

        sync(usr);
        total -= amt;
        shares[usr] -= amt;
        token.safeTransfer(dst, amt);
    }

    /*
    function calc(address usr) public view returns (uint256) {
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        if (total > 0) {
            a += rate * (t - last) * R / total;
        }
        return rewards[usr] + shares[usr] * (a - accs[usr]) / R;
    }
    */

    function sync(address usr) public returns (uint256 amt) {
        uint256 t = Math.min(block.timestamp, exp);
        // TODO: if total = 0?
        if (total > 0) {
            acc += rate * (t - last) * R / total;
        }
        last = t;

        if (usr != address(0)) {
            amt = shares[usr] * (acc - accs[usr]) / R;
            accs[usr] = acc;
            rewards[usr] += amt;
            if (!stopped) {
                keep += amt;
            }
        }
    }

    function take(address usr) public returns (uint256 amt) {
        sync(usr);
        amt = rewards[usr];
        if (amt > 0) {
            rewards[usr] = 0;
            keep -= amt;
            token.safeTransfer(usr, amt);
        }
    }

    function restake(address usr) external live returns (uint256 amt) {
        require(block.timestamp < exp, "expired");

        sync(usr);
        amt = rewards[usr];
        if (amt > 0) {
            total += amt;
            shares[usr] += amt;
            keep -= amt;
            rewards[usr] = 0;
        }
    }

    // TODO: live?
    function pay(uint256 amt) external live {
        sync(address(0));

        token.safeTransferFrom(msg.sender, address(this), amt);
        if (block.timestamp < exp) {
            amt += rate * (exp - block.timestamp);
        }
        rate = amt / dur;

        // TODO: update time stamps?
    }

    // TODO: live?
    // TODO: schedule new rates
    function roll() external live {
        require(block.timestamp < exp, "expired");
        require(rate > 0, "rate = 0");

        sync(address(0));
        token.safeTransferFrom(msg.sender, address(this), rate * dur);
        exp += dur;
    }

    function cover(address src, uint256 amt, address dst) external auth {
        require(stopped, "not stopped");

        token.safeTransferFrom(src, address(this), amt);

        uint256 bal = token.balanceOf(address(this));
        token.safeTransfer(dst, bal - keep);
    }

    // TODO: token recover
    // TODO: emergency clean up
    function stop() external auth live {
        require(block.timestamp < exp, "expired");

        uint256 a0 = acc;
        sync(address(0));
        uint256 a1 = acc;

        keep += (a1 - a0) * total / R;

        last = block.timestamp;
        exp = block.timestamp;
        // TODO: stop rewards?
        stopped = true;
    }
}
