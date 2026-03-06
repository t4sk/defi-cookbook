// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "./lib/Auth.sol";

// TODO: gas golf

contract Stake is Auth {
    using SafeTransfer for IERC20;

    event Deposit(address indexed usr, uint256 amt);
    event Withdraw(address indexed usr, uint256 amt);
    event Take(address indexed usr, uint256 amt);
    event Refund(address indexed usr, uint256 amt);
    event Restake(address indexed usr, uint256 amt);
    event Inc(uint256 amt);
    event Roll(uint256 rate);
    event Stop();
    event Settle(uint256 state);
    event Cover(uint256 amt);
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
        Cover,
        Exit
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
    mapping(address usr => uint256 amt) public rewards;

    // Next rate
    uint256 public nextRate;
    // Timestamp to apply next rate
    uint256 public next;
    // Authorized account to call roll
    address public insuree;

    // Rewards remaining after stop
    uint256 public keep;
    // Total amount of rewards deposited
    uint256 public topped;
    // Total amount of rewards claimed (transferred out or restaked)
    uint256 public paid;

    modifier live() {
        require(state == State.Live, "not live");
        require(block.timestamp < exp, "expired");
        _;
    }

    constructor(address _token, uint256 _dur, address _insuree, uint256 _dust) {
        token = IERC20(_token);
        last = block.timestamp;
        exp = block.timestamp + _dur;
        dur = _dur;
        state = State.Live;
        insuree = _insuree;
        dust = _dust;

        // Ensures reward rate when total < rate * dur is > 0
        require(dust / dur > 0, "dust / dur = 0");

        // Insuree can claim rewards while no one staked
        // Some calculations are done with total + 1 to account for this share
        shares[address(this)] = 1;
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

    // Calculate claimable rewards of a user
    function calc(address usr) external view returns (uint256) {
        // Cap timestamp to exp
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        uint256 tot = total;
        uint256 cap = tot / dur;
        if (next > 0 && next <= t) {
            a += Math.min(rate, cap) * (next - last) * R / (tot + 1);
            a += Math.min(nextRate, cap) * (t - next) * R / (tot + 1);
        } else {
            a += Math.min(rate, cap) * (t - last) * R / (tot + 1);
        }
        return rewards[usr] + shares[usr] * (a - accs[usr]) / R;
    }

    // Sync rewards
    function sync(address usr) public returns (uint256 amt) {
        // Cap timestamp to exp
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        uint256 tot = total;
        // Let r = rate to pay
        //     c = total rewards in this cycle
        //     dt = delta time since last update
        // If tot <= c for the full duration
        // insuree is better off not paying for an insurance
        // So ensure total rewards paid <= tot
        // by setting r = tot / dur
        // r * dt <= c / dur * dt
        // sum(r * dt) = tot <= sum(c / dur * dt) = c
        uint256 cap = tot / dur;
        // Save excess for insuree
        uint256 saved = 0;

        if (next > 0 && next <= t) {
            uint256 r = Math.min(rate, cap);
            uint256 nr = Math.min(nextRate, cap);
            uint256 dt0 = next - last;
            uint256 dt1 = t - next;
            a += r * dt0 * R / (tot + 1);
            a += nr * dt1 * R / (tot + 1);
            saved = (rate - r) * dt0 + (nextRate - nr) * dt1;
            rate = nextRate;
            nextRate = 0;
            next = 0;
        } else {
            uint256 r = Math.min(rate, cap);
            uint256 dt = t - last;
            a += r * dt * R / (tot + 1);
            saved = (rate - r) * dt;
        }
        acc = a;
        last = t;

        if (saved > 0) {
            keep += saved;
        }

        if (usr != address(0)) {
            amt = shares[usr] * (a - accs[usr]) / R;
            accs[usr] = a;
            rewards[usr] += amt;
        }
    }

    function deposit(address usr, uint256 amt) external auth live {
        require(usr != address(this), "invalid usr");
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
    {
        require(usr != address(this), "invalid usr");
        sync(usr);
        total -= amt;
        shares[usr] -= amt;
        require(shares[usr] == 0 || shares[usr] >= dust, "dust");
        token.safeTransfer(dst, amt);
        emit Withdraw(usr, amt);
    }

    // Claim rewards
    function take() public returns (uint256 amt) {
        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            rewards[msg.sender] = 0;
            paid += amt;
            token.safeTransfer(msg.sender, amt);
        }
        emit Take(msg.sender, amt);
    }

    // Restake rewards
    function restake() external live returns (uint256 amt) {
        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            rewards[msg.sender] = 0;
            paid += amt;
            total += amt;
            shares[msg.sender] += amt;
            require(shares[msg.sender] >= dust, "dust");
        }
        emit Restake(msg.sender, amt);
    }

    // Refund to insuree
    function refund() external returns (uint256 amt) {
        require(msg.sender == insuree, "not insuree");

        sync(address(this));
        amt = rewards[address(this)];
        if (amt > 0) {
            rewards[address(this)] = 0;
            paid += amt;
        }

        if (keep > 0) {
            amt += keep;
            paid += keep;
            keep = 0;
        }

        if (amt > 0) {
            token.safeTransfer(msg.sender, amt);
        }
        emit Refund(msg.sender, amt);
    }

    // Increase reward emission rate
    function inc(uint256 amt) external live {
        sync(address(0));
        token.safeTransferFrom(msg.sender, address(this), amt);

        uint256 t = next > 0 ? next : exp;
        uint256 delta = amt / (t - block.timestamp);
        require(delta > 0, "delta rate = 0");
        rate += delta;
        topped += amt;

        emit Inc(amt);
    }

    // Extend insurance and schedule new rate
    function roll(uint256 r) external live {
        require(msg.sender == insuree, "not insuree");
        require(rate > 0, "rate = 0");
        require(next == 0, "rolled");
        // Allow rolling when time remaining is < half the duration
        require(exp - block.timestamp < dur / 2, "too early");

        sync(address(0));
        if (r > 0) {
            token.safeTransferFrom(msg.sender, address(this), r * dur);
            topped += r * dur;
        }

        nextRate = r;
        next = exp;
        exp += dur;

        emit Roll(r);
    }

    // Stop reward emissions
    function stop() external auth live {
        sync(address(0));
        keep += pot();
        exp = block.timestamp;
        state = State.Stopped;
        emit Stop();
    }

    // Decide who to pay (insuree or stakers)
    function settle(State s) external auth {
        require(state == State.Stopped, "not stopped");
        require(s == State.Cover || s == State.Exit, "invalid next state");
        state = s;
        emit Settle(uint256(s));
    }

    // Pay insuree
    function cover(address src, uint256 amt, address dst)
        external
        auth
        returns (uint256)
    {
        require(state == State.Cover, "invalid state");

        if (amt > 0) {
            token.safeTransferFrom(src, address(this), amt);
        }

        amt += total;
        total = 0;

        token.safeTransfer(dst, amt);

        emit Cover(amt);
        return amt;
    }

    // Pay stakers
    function exit() external returns (uint256 amt) {
        // Expired without call to stop or settled
        if (state == State.Live) {
            require(exp < block.timestamp, "not expired");
        } else {
            require(state == State.Exit, "invalid state");
        }

        sync(msg.sender);

        // Rewards
        uint256 r = rewards[msg.sender];
        rewards[msg.sender] = 0;
        paid += r;

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
            uint256 bal = token.balanceOf(address(this));
            // topped >= paid
            // topped - paid = future reward emissions + rewards claimable by stakers
            // bal >= staked + topped - paid
            uint256 need = total + topped - paid;
            token.safeTransfer(msg.sender, bal - need);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, bal);
        }
    }
}
