// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math} from "../lib/Math.sol";

contract Stake {
    using SafeTransfer for IERC20;

    // TODO: events
    // TODO: gas golf

    // Rate scale
    uint256 private constant R = 1e18;
    IERC20 public immutable token;

    bool public stopped;
    mapping(address => bool) public auths;

    // Total staked
    uint256 public total;
    // user => staked amount
    mapping(address usr => uint256 amt) public shares;

    // Last updated time
    uint256 public last;
    // Expiration time
    uint256 public exp;
    // Rate of token emission per second
    uint256 public rate;
    // Rate accumulator
    uint256 public acc;
    mapping(address usr => uint256 acc) public accs;
    mapping(address usr => uint256 amt) public rewards;

    modifier auth() {
        require(auths[msg.sender], "not auth");
        _;
    }

    modifier live() {
        require(!stopped, "stopped");
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        // TODO:emit
        auths[msg.sender] = true;
        last = block.timestamp;
        exp = block.timestamp;
    }

    function allow(address usr) external auth {
        auths[usr] = true;
    }

    function deny(address usr) external auth {
        auths[usr] = false;
    }

    function deposit(address usr, uint256 amt) external auth live {
        // TODO: delay -> deposit
        require(block.timestamp < exp, "expired");
        // TODO: handle rebase token (inf deposit + checking bal diff)?
        token.safeTransferFrom(msg.sender, address(this), amt);

        // TODO: restake
        updateRewards(usr);
        total += amt;
        shares[usr] += amt;
    }

    function withdraw(address usr, uint256 amt) external auth live {
        // TODO: delay -> withdraw
        updateRewards(usr);
        total -= amt;
        shares[usr] -= amt;

        // TODO: handle rebase token (inf deposit + checking bal diff)?
        token.safeTransfer(usr, amt);
    }

    function calcRewards(address usr) public view returns (uint256) {
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        if (total > 0) {
            a += rate * (t - last) * R / total;
        }
        return rewards[usr] + shares[usr] * (a - accs[usr]) / R;
    }

    function updateRewards(address usr) public returns (uint256 amt) {
        uint256 t = Math.min(block.timestamp, exp);
        // TODO: if total = 0?
        if (total > 0) {
            acc += rate * (t - last) * R / total;
        }
        last = t;

        amt = shares[usr] * (acc - accs[usr]) / R;
        accs[usr] = acc;
        rewards[usr] += amt;
    }

    function getRewards(address usr) public returns (uint256 amt) {
        // TODO: updateRewards(usr);?
        amt = rewards[usr];
        if (amt > 0) {
            rewards[usr] = 0;
            token.safeTransfer(usr, amt);
        }
    }

    function pay() external {}

    // TODO
    // function extend() external {}

    function cut() external auth {
        require(stopped, "not stopped");
        // TODO: stopped?
        // delete withdrawal queue + pull funds from withdrawal queue
    }

    // Insurer - stakers
    // get rewards

    // restake (get rewards + deposit (skip withdrawal queue))

    // TODO: emergency clean up
    function stop() external auth live {
        stopped = true;
    }
}
