// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Factory} from "@src/insurance/Factory.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {WithdrawDelay} from "@src/insurance/WithdrawDelay.sol";

address constant INSUREE = address(10);
uint256 constant DUR = 30 days;
uint256 constant DUST = 1e18;
uint256 constant COV = 1;
uint256 constant EPOCH = 3 days;

contract Handler is Test {
    Stake private immutable stake;
    WithdrawDelay private immutable wd;
    ERC20 private immutable token;

    // TODO: insuree + auth
    address[] public users = [address(1), address(2), address(3), address(4)];
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
    }

    modifier prank(uint256 seed) {
        user = users[seed % users.length];
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function live() private returns (bool) {
        return
            block.timestamp < stake.exp() && stake.state() == Stake.State.Live;
    }

    function sync(uint256 seed) external prank(seed) {
        stake.sync(user);
    }

    function deposit(uint256 seed, uint256 amt) external prank(seed) {
        if (!live()) {
            return;
        }
        amt = bound(amt, stake.dust(), 100e18);
        uint256 bal = token.balanceOf(user);
        if (amt > bal) {
            token.mint(user, amt - bal);
        }
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
                || (stake.state() == Stake.State.Live
                    && stake.exp() < block.timestamp)
        ) {
            stake.exit();
        }
    }

    function queue(uint256 seed, uint256 amt) external prank(seed) {
        if (wd.state() != WithdrawDelay.State.Live || !live()) {
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

        // Already unlocked
        if (amt == 0) {
            return;
        }
        WithdrawDelay.State wdState = wd.state();
        if (wdState == WithdrawDelay.State.Live) {
            if (block.timestamp < exp) return;
        } else if (wdState == WithdrawDelay.State.Stopped) {
            if (wd.last() < exp && wd.dumped() > 0) return;
        } else if (wdState == WithdrawDelay.State.Covered) {
            if (wd.last() < exp) return;
        }
        // Refilled: all locks unlockable

        wd.unlock(i);

        if (ixs.length > 1) {
            ixs[i] = ixs[n - 1];
        }
        ixs.pop();
    }

    /*
       TODO
       inc
      refund
    function stop() external {
        if (stake.state() != Stake.State.Live || block.timestamp >= stake.exp())
        return;
        stake.stop();
    }

    function dump() external {
        if (wd.state() != WithdrawDelay.State.Live) return;
        wd.dump();
    }

    function settle(uint256 stateSeed) external {
        if (stake.state() != Stake.State.Stopped) return;
        stake.settle(stateSeed % 2 == 0 ? Stake.State.Cover : Stake.State.Exit);
    }

    function cover() external {
        if (wd.state() != WithdrawDelay.State.Stopped || stake.state() != Stake.State.Cover) return;
        wd.cover(address(0x99));
    }

    function refill() external {
        if (wd.state() != WithdrawDelay.State.Stopped || stake.state() != Stake.State.Exit) return;
        wd.refill();
    }
    */

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
        stake.allow(address(handler));
        wd.allow(address(handler));
        targetContract(address(handler));
    }

    // TODO: invariants

    function invariant_stake_bal() public view {
        uint256 bal = token.balanceOf(address(stake));
        uint256 need = stake.total() + stake.topped() - stake.paid();
        assertGe(bal, need);
    }

    function invariant_paid_le_topped() public view {
        assertLe(stake.paid(), stake.topped());
    }

    function invariant_wd_balance_covers_keep() public view {
        assertGe(token.balanceOf(address(wd)), wd.keep());
    }

    function invariant_dumped_le_keep() public view {
        assertLe(wd.dumped(), wd.keep());
    }

    function invariant_dumped_requires_stopped() public view {
        if (wd.dumped() > 0) {
            assertTrue(wd.state() == WithdrawDelay.State.Stopped);
        }
    }

    function invariant_system_solvency() public view {
        uint256 bal =
            token.balanceOf(address(stake)) + token.balanceOf(address(wd));
        uint256 need = stake.total() + stake.topped() - stake.paid() + wd.keep();
        assertGe(bal, need);
    }
}
