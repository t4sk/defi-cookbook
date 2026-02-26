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
    // Reward duration
    uint256 public immutable dur;

    bool public stopped;

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
    // User => last rate accumulator
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

        sync(usr);
        total += amt;
        shares[usr] += amt;
    }

    function withdraw(address usr, address dst, uint256 amt) external live {
        // Stakers can withdraw without delay after expiry
        if (block.timestamp < exp) {
            require(auths[msg.sender], "not auth");
        } else {
            require(usr == msg.sender, "not msg.sender");
        }

        sync(usr);
        total -= amt;
        shares[usr] -= amt;
        token.safeTransfer(dst, amt);
    }

    function calc(address usr) public view returns (uint256) {
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        if (total > 0) {
            a += rate * (t - last) * R / total;
        }
        return rewards[usr] + shares[usr] * (a - accs[usr]) / R;
    }

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

    function take() public returns (uint256 amt) {
        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            rewards[msg.sender] = 0;
            keep -= amt;
            token.safeTransfer(msg.sender, amt);
        }
    }

    function restake() external live returns (uint256 amt) {
        require(block.timestamp < exp, "expired");

        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            total += amt;
            shares[msg.sender] += amt;
            keep -= amt;
            rewards[msg.sender] = 0;
        }
    }

    function pay(uint256 amt) external live {
        require(block.timestamp < exp, "expired");

        sync(address(0));

        token.safeTransferFrom(msg.sender, address(this), amt);
        if (block.timestamp < exp) {
            amt += rate * (exp - block.timestamp);
        }
        rate = amt / dur;
    }

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

        // bal >= total + amount pulled from src + rewards
        uint256 bal = token.balanceOf(address(this));
        token.safeTransfer(dst, bal - keep);
    }

    function stop() external auth live {
        require(block.timestamp < exp, "expired");

        uint256 a0 = acc;
        sync(address(0));
        uint256 a1 = acc;

        keep += (a1 - a0) * total / R;

        // Stop rewards
        last = block.timestamp;
        exp = block.timestamp;
        stopped = true;
    }

    function recover(address _token) external auth {
        if (_token == address(0)) {
            (bool ok,) = msg.sender.call{value: address(this).balance}("");
            require(ok, "send ETH failed");
        } else if (_token == address(token)) {
            // TODO: fix
            uint256 bal = token.balanceOf(address(this));
            token.safeTransfer(msg.sender, bal - keep);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, bal);
        }
    }
}
