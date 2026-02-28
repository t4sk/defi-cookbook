// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "./lib/Auth.sol";

// TODO: gas golf
// TODO: overflow dos?

contract Stake is Auth {
    using SafeTransfer for IERC20;

    event Deposit(address indexed usr, uint256 amt);
    event Withdraw(address indexed usr, uint256 amt);
    event Take(address indexed usr, uint256 amt);
    event Restake(address indexed usr, uint256 amt);
    event Inc(uint256 amt);
    event Roll();
    event Stop();
    event Settle(uint256 state);
    event Cover();
    event Exit(address indexed usr, uint256 amt);

    // Rate scale
    uint256 private constant R = 1e18;
    IERC20 public immutable token;
    // Reward duration
    uint256 public immutable dur;

    enum State {
        Live,
        Stopped,
        Covered,
        NotCovered
    }

    State public state;

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

    // Future rate
    uint256 public futRate;
    // Timestamp to apply future rate
    uint256 public fut;
    // Authorized account to call roll
    address public roller;

    modifier live() {
        require(state == State.Live, "not live");
        _;
    }

    modifier time() {
        require(block.timestamp < exp, "expired");
        _;
    }

    constructor(address _token, uint256 _dur, address _roller) {
        token = IERC20(_token);
        last = block.timestamp;
        exp = block.timestamp + _dur;
        dur = _dur;
        state = State.Live;
        roller = _roller;
    }

    function stopped() public view returns (bool) {
        return uint256(state) > uint256(State.Live);
    }

    function calc(address usr) external view returns (uint256) {
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        if (total > 0) {
            if (fut != 0 && fut <= t) {
                a += rate * (fut - last) * R / total;
                a += futRate * (t - fut) * R / total;
            } else {
                a += rate * (t - last) * R / total;
            }
        }
        return rewards[usr] + shares[usr] * (a - accs[usr]) / R;
    }

    function sync(address usr) public returns (uint256 amt) {
        uint256 t = Math.min(block.timestamp, exp);

        // TODO: fix total = 0 causes reward leakage?
        // TODO: check code
        if (total > 0) {
            if (fut != 0 && fut <= t) {
                acc += rate * (fut - last) * R / total;
                acc += futRate * (t - fut) * R / total;

                rate = futRate;
                futRate = 0;
                fut = 0;
            } else {
                acc += rate * (t - last) * R / total;
            }
        }
        last = t;

        if (usr != address(0)) {
            amt = shares[usr] * (acc - accs[usr]) / R;
            accs[usr] = acc;
            rewards[usr] += amt;
            if (!stopped()) {
                keep += amt;
            }
        }
    }

    function deposit(address usr, uint256 amt) external auth live time {
        token.safeTransferFrom(msg.sender, address(this), amt);
        sync(usr);
        total += amt;
        shares[usr] += amt;
        emit Deposit(usr, amt);
    }

    function withdraw(address usr, address dst, uint256 amt)
        external
        auth
        live
        time
    {
        sync(usr);
        total -= amt;
        shares[usr] -= amt;
        token.safeTransfer(dst, amt);
        emit Withdraw(usr, amt);
    }

    function take() public returns (uint256 amt) {
        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            keep -= amt;
            rewards[msg.sender] = 0;
            token.safeTransfer(msg.sender, amt);
        }
        emit Take(msg.sender, amt);
    }

    function restake() external live time returns (uint256 amt) {
        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            keep -= amt;
            rewards[msg.sender] = 0;
            total += amt;
            shares[msg.sender] += amt;
        }
        emit Restake(msg.sender, amt);
    }

    // TODO: dynamic rate setter
    function inc(uint256 amt) external live time {
        sync(address(0));
        token.safeTransferFrom(msg.sender, address(this), amt);
        // TODO:recover dust?
        rate += amt / (exp - block.timestamp);
        emit Inc(amt);
    }

    function roll(uint256 f) external live time {
        require(msg.sender == roller, "not roller");
        require(rate > 0, "rate = 0");

        sync(address(0));
        if (f > 0) {
            token.safeTransferFrom(msg.sender, address(this), f * dur);
        }

        futRate = f;
        fut = exp;

        // Allow rolling when time remaining is < half the duration
        require(exp - block.timestamp < dur / 2, "too early");
        exp += dur;

        emit Roll();
    }

    function stop() external auth live time {
        uint256 a0 = acc;
        sync(address(0));
        uint256 a1 = acc;

        // TODO: need high precision?
        // Round up by 1
        keep += (a1 - a0) * total / R + 1;

        // Stop rewards
        last = block.timestamp;
        exp = block.timestamp;
        state = State.Stopped;
        emit Stop();
    }

    function settle(State s) external auth {
        require(state == State.Stopped, "not stopped");
        require(
            s == State.Covered || s == State.NotCovered, "invalid next state"
        );
        state = s;
        emit Settle(uint256(s));
    }

    function cover(address src, uint256 amt, address dst) external auth {
        require(state == State.Covered, "invalid state");

        token.safeTransferFrom(src, address(this), amt);

        // bal >= total + amount pulled from src + rewards to be paid out
        uint256 bal = token.balanceOf(address(this));
        token.safeTransfer(dst, bal - keep);
        emit Cover();
    }

    function exit() external returns (uint256 amt) {
        // Expired without call to stop or settled
        if (state == State.Live) {
            require(exp < block.timestamp, "not expired");
        } else {
            require(state == State.NotCovered, "invalid state");
        }

        sync(msg.sender);

        // Rewards
        uint256 r = rewards[msg.sender];
        rewards[msg.sender] = 0;
        // Account for imprecision after stop
        if (!stopped()) {
            keep -= r;
        } else {
            keep -= Math.min(r, keep);
        }

        // Staked
        uint256 s = shares[msg.sender];
        shares[msg.sender] = 0;
        total -= s;

        amt = r + s;

        token.safeTransfer(msg.sender, amt);

        emit Exit(msg.sender, amt);
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
