// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Factory} from "@src/insurance/Factory.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {WithdrawDelay} from "@src/insurance/WithdrawDelay.sol";

address constant AUTH = address(10);
address constant INSUREE = address(11);
uint256 constant DUR = 30 days;
uint256 constant DUST = 1e18;
uint256 constant COV = 2;
uint256 constant EPOCH = 3 days;

contract Handler is Test {
    Stake private immutable stake;
    WithdrawDelay private immutable wd;
    ERC20 private immutable token;

    address[] public users = [address(1), address(2), address(3)];
    address private user;
    mapping(address => uint256[]) private locks;

    constructor(Stake _stake, WithdrawDelay _wd, ERC20 _token) {
        stake = _stake;
        wd = _wd;
        token = _token;
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            token.approve(address(stake), type(uint256).max);
        }

        token.approve(address(stake), type(uint256).max);
    }

    modifier prank(uint256 seed) {
        user = users[seed % users.length];
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function live() private returns (bool) {
        return block.timestamp < stake.exp() && !stake.stopped();
    }

    function top(address usr, uint256 amt) private {
        uint256 bal = token.balanceOf(usr);
        if (amt > bal) {
            token.mint(usr, amt - bal);
        }
    }

    function sync(uint256 seed) external prank(seed) {
        stake.sync(user);
    }

    function deposit(uint256 seed, uint256 amt) external prank(seed) {
        if (!live()) {
            return;
        }
        amt = bound(amt, stake.dust(), 100e18);
        top(user, amt);
        stake.deposit(amt);
    }

    function take(uint256 seed) external prank(seed) {
        stake.take();
    }

    function restake(uint256 seed) external prank(seed) {
        if (!live()) {
            return;
        }
        if (stake.shares(user) >= stake.dust()) {
            stake.restake();
        }
    }

    function exit(uint256 seed) external prank(seed) {
        if (
            stake.state() == Stake.State.Exit
                || (!stake.stopped() && stake.exp() < block.timestamp)
        ) {
            stake.exit();
        }
    }

    function queue(uint256 seed, uint256 amt) external prank(seed) {
        if (wd.stopped() || !live()) {
            return;
        }
        uint256 staked = stake.shares(user);
        if (staked == 0) {
            return;
        }
        amt = bound(amt, 1, staked);
        uint256 rem = staked - amt;
        if (rem > 0 && rem < stake.dust()) {
            amt = staked;
        }
        uint256 i = wd.queue(amt);
        locks[user].push(i);
    }

    function unlock(uint256 seed, uint256 i) external prank(seed) {
        uint256[] storage ixs = locks[user];
        uint256 n = ixs.length;
        if (n == 0) {
            return;
        }

        i = bound(i, 0, n - 1);
        (uint256 amt, uint256 exp) = wd.locks(user, i);

        if (amt == 0) {
            return;
        }

        if (wd.state() == WithdrawDelay.State.Live) {
            if (block.timestamp < exp) {
                return;
            }
        } else if (wd.state() == WithdrawDelay.State.Stopped) {
            if (wd.last() < exp && wd.dumped() > 0) {
                return;
            }
        } else if (wd.state() == WithdrawDelay.State.Covered) {
            if (wd.last() < exp) {
                return;
            }
        }

        wd.unlock(i);

        if (ixs.length > 1) {
            ixs[i] = ixs[n - 1];
        }
        ixs.pop();
    }

    function refund() external {
        vm.prank(INSUREE);
        stake.refund();
    }

    function inc(uint256 amt) external {
        if (!live()) {
            return;
        }
        amt = bound(amt, stake.dur(), 10e18);
        top(address(this), amt);
        stake.inc(amt);
    }

    function roll(uint256 rate) external {
        if (
            !live() || stake.rate() == 0 || stake.next() > 0
                || block.timestamp + stake.dur() / 2 <= stake.exp()
        ) {
            return;
        }
        rate = bound(rate, 0, 1e18);
        uint256 amt = rate * stake.dur();
        top(INSUREE, amt);
        vm.prank(INSUREE);
        stake.roll(rate);
    }

    function stop() external {
        if (!live()) {
            return;
        }
        vm.startPrank(AUTH);
        stake.stop();
        wd.stop();
        vm.stopPrank();
    }

    function cover() external {
        if (stake.state() != Stake.State.Stopped) {
            return;
        }
        vm.startPrank(AUTH);
        stake.settle(Stake.State.Cover);
        wd.cover(INSUREE);
        vm.stopPrank();
    }

    function refill() external {
        if (stake.state() != Stake.State.Stopped) {
            return;
        }
        vm.startPrank(AUTH);
        stake.settle(Stake.State.Exit);
        wd.refill();
        vm.stopPrank();
    }

    function recover(uint256 amt) external {
        amt = bound(amt, 0, 1e18);
        top(address(this), 2 * amt);
        token.transfer(address(stake), amt);
        token.transfer(address(wd), amt);

        vm.startPrank(AUTH);
        stake.recover(address(token));
        wd.recover(address(token));
        vm.stopPrank();
    }

    function warp(uint256 secs) external {
        secs = bound(secs, 0, stake.dur());
        vm.warp(block.timestamp + secs);
    }
}

contract SystemInvariantTest is Test {
    ERC20 token;
    Factory factory;
    Stake stake;
    WithdrawDelay wd;
    Handler handler;

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        factory = new Factory();

        (address s, address w) =
            factory.create(address(token), INSUREE, DUR, DUST, COV, EPOCH);
        stake = Stake(s);
        wd = WithdrawDelay(w);

        token.mint(INSUREE, 1e18 * DUR);
        vm.prank(INSUREE);
        token.approve(address(stake), type(uint256).max);
        vm.prank(INSUREE);
        stake.inc(1e18 * DUR);

        handler = new Handler(stake, wd, token);
        stake.allow(AUTH);
        wd.allow(AUTH);
        targetContract(address(handler));
    }

    function invariant_stake_bal() public view {
        uint256 bal = token.balanceOf(address(stake));
        uint256 need = stake.total() + stake.topped() - stake.paid();
        assertGe(bal, need);

        uint256 rewards = stake.pot() + stake.calc(address(stake));
        for (uint256 i = 0; i < 3; i++) {
            rewards += stake.calc(handler.users(i));
        }
        assertGe(bal, stake.total() + rewards);

        assertGe(stake.topped(), rewards + stake.paid());
    }

    function invariant_wd_balance_covers_keep() public view {
        assertGe(token.balanceOf(address(wd)), wd.keep());
    }

    function invariant_dumped_le_keep() public view {
        assertLe(wd.dumped(), wd.keep());
    }

    function invariant_sys_bal() public view {
        uint256 bal =
            token.balanceOf(address(stake)) + token.balanceOf(address(wd));
        uint256 need = stake.total() + stake.topped() - stake.paid() + wd.keep();
        assertGe(bal, need);
    }
}
