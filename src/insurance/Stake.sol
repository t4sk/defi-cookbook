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
    // Minimum amount to deposit and must remain in stake
    uint256 public immutable dust;

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

    // Next rate
    uint256 public nextRate;
    // Timestamp to apply next rate
    uint256 public next;
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

    constructor(address _token, uint256 _dur, address _roller, uint256 _dust) {
        token = IERC20(_token);
        last = block.timestamp;
        exp = block.timestamp + _dur;
        dur = _dur;
        state = State.Live;
        roller = _roller;
        dust = _dust;
    }

    function stopped() public view returns (bool) {
        return uint256(state) > uint256(State.Live);
    }

    // Remaining rewards
    function pot() public view returns (uint256 rem) {
        if (next > 0) {
            if (block.timestamp < next) {
                rem = rate * (next - block.timestamp);
                rem += nextRate * dur;
            } else if (block.timestamp < exp) {
                rem = nextRate * (exp - block.timestamp);
            }
        } else {
            if (block.timestamp < exp) {
                rem = rate * (exp - block.timestamp);
            }
        }
    }

    function calc(address usr) external view returns (uint256) {
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        if (next > 0 && next <= t) {
            if (total > 0) {
                a += rate * (next - last) * R / total;
                a += nextRate * (t - next) * R / total;
            }
        } else {
            // Next rate is not set or current time < next rate update time
            if (total > 0) {
                a += rate * (t - last) * R / total;
            }
        }
        return rewards[usr] + shares[usr] * (a - accs[usr]) / R;
    }

    function sync(address usr) public returns (uint256 amt) {
        uint256 t = Math.min(block.timestamp, exp);

        if (next > 0 && next <= t) {
            if (total > 0) {
                acc += rate * (next - last) * R / total;
                acc += nextRate * (t - next) * R / total;
            }
            rate = nextRate;
            nextRate = 0;
            next = 0;
        } else {
            if (total > 0) {
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
        require(amt >= dust, "dust");
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
        require(shares[usr] == 0 || shares[usr] >= dust, "dust");
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
        // TODO: clean up
        if (next > 0) {
            rate += amt / (next - block.timestamp);
        } else {
            rate += amt / (exp - block.timestamp);
        }
        emit Inc(amt);
    }

    function roll(uint256 r) external live time {
        require(msg.sender == roller, "not roller");
        require(rate > 0, "rate = 0");
        require(next == 0, "already rolled");

        sync(address(0));
        if (r > 0) {
            token.safeTransferFrom(msg.sender, address(this), r * dur);
        }

        nextRate = r;
        next = exp;

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
        if (stopped()) {
            r = Math.min(r, keep);
        }
        keep -= r;

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
            uint256 a0 = acc;
            sync(address(0));
            uint256 a1 = acc;

            uint256 k = keep + (a1 - a0) * total / R + 1;
            uint256 bal = token.balanceOf(address(this));
            uint256 amt = bal - (total + k + pot());

            token.safeTransfer(msg.sender, amt);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, bal);
        }
    }
}
