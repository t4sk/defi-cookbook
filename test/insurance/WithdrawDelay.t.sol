// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {WithdrawDelay} from "@src/insurance/WithdrawDelay.sol";

contract WithdrawDelayTest is Test {
    ERC20 token;
    Stake stake;
    WithdrawDelay with;

    uint256 constant DUR = 30 * 24 * 3600;
    uint256 constant DUST = 1e18;
    uint256 constant COV = 1;
    uint256 constant EPOCH = 1 days;
    address constant INSUREE = address(10);
    address[] users = [address(100), address(101), address(102)];

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        stake = new Stake(address(token), INSUREE, DUR, DUST, COV);
        with = new WithdrawDelay(address(stake), EPOCH);

        stake.allow(address(with));

        token.mint(INSUREE, 1e18 * DUR);
        vm.prank(INSUREE);
        token.approve(address(stake), type(uint256).max);
        vm.prank(INSUREE);
        stake.inc(1e18 * DUR);

        for (uint256 i = 0; i < users.length; i++) {
            token.mint(users[i], 100 * 1e18);
            vm.prank(users[i]);
            token.approve(address(stake), type(uint256).max);
            vm.prank(users[i]);
            stake.deposit(10 * DUST);
        }
    }

    function test_constructor() public view {
        assertEq(address(with.token()), address(token));
        assertEq(address(with.stake()), address(stake));
        assertEq(with.EPOCH(), EPOCH);
        assertEq(with.keep(), 0);
        assertEq(with.dumped(), 0);
        assertFalse(with.stopped());
    }

    function test_queue() public {
        address usr = users[0];
        uint256 amt = 5 * DUST;
        vm.prank(usr);
        uint256 i = with.queue(amt);

        assertEq(i, 0);
        assertEq(with.counts(usr), 1);
        assertEq(with.keep(), amt);
        (uint256 lockAmt, uint256 lockExp) = with.locks(usr, i);
        assertEq(lockAmt, amt);

        uint256 curr = (block.timestamp / EPOCH) * EPOCH;
        assertEq(lockExp, curr + 2 * EPOCH);
    }

    function test_queue_stopped() public {
        with.stop();
        vm.expectRevert("not live");
        vm.prank(users[0]);
        with.queue(DUST);
    }

    function test_queue_multiple() public {
        address usr = users[0];
        vm.prank(usr);
        uint256 i0 = with.queue(3 * DUST);
        vm.prank(usr);
        uint256 i1 = with.queue(2 * DUST);

        assertEq(i0, 0);
        assertEq(i1, 1);
        assertEq(with.counts(usr), 2);
        assertEq(with.keep(), 5 * DUST);
    }

    function test_queue_multiple_users() public {
        vm.prank(users[0]);
        with.queue(3 * DUST);
        vm.prank(users[1]);
        with.queue(4 * DUST);

        assertEq(with.counts(users[0]), 1);
        assertEq(with.counts(users[1]), 1);
        assertEq(with.keep(), 7 * DUST);
    }

    function test_unlock() public {
        address usr = users[0];
        uint256 amt = 5 * DUST;
        vm.prank(usr);
        uint256 i = with.queue(amt);

        skip(2 * EPOCH);

        uint256 balBefore = token.balanceOf(usr);
        vm.prank(usr);
        with.unlock(i);

        assertEq(token.balanceOf(usr), balBefore + amt);
        assertEq(with.keep(), 0);
        (uint256 lockAmt,) = with.locks(usr, i);
        assertEq(lockAmt, 0);
    }

    function test_unlock_not_expired() public {
        address usr = users[0];
        vm.prank(usr);
        uint256 i = with.queue(DUST);

        skip(EPOCH);

        vm.expectRevert("lock not expired");
        vm.prank(usr);
        with.unlock(i);
    }

    function test_unlock_no_lock() public {
        vm.expectRevert("index out of bound");
        vm.prank(users[0]);
        with.unlock(0);
    }

    function test_unlock_already_unlocked() public {
        address usr = users[0];
        vm.prank(usr);
        uint256 i = with.queue(DUST);
        skip(2 * EPOCH);

        vm.prank(usr);
        with.unlock(i);

        vm.expectRevert("lock amt = 0");
        vm.prank(usr);
        with.unlock(i);
    }

    function test_unlock_after_stop_old_lock() public {
        address usr = users[0];
        vm.prank(usr);
        uint256 i = with.queue(DUST);

        skip(3 * EPOCH);
        with.stop();

        vm.prank(usr);
        with.unlock(i);
    }

    function test_unlock_after_stop_recent_lock() public {
        address usr = users[0];

        vm.prank(usr);
        uint256 i = with.queue(DUST);

        skip(EPOCH);
        with.stop();

        skip(EPOCH);

        vm.expectRevert("cannot unlock");
        vm.prank(usr);
        with.unlock(i);
    }

    function test_stop() public {
        vm.prank(users[0]);
        with.queue(3 * DUST);
        vm.prank(users[1]);
        with.queue(2 * DUST);

        uint256 amt = with.stop();

        assertEq(amt, 5 * DUST);
        assertTrue(with.stopped());
        assertEq(with.dumped(), 5 * DUST);
        assertEq(with.keep(), 5 * DUST);
    }

    function test_stop_no_pending() public {
        uint256 amt = with.stop();
        assertEq(amt, 0);
        assertTrue(with.stopped());
        assertEq(with.dumped(), 0);
    }

    function test_stop_buckets_shift() public {
        vm.prank(users[0]);
        with.queue(3 * DUST);

        skip(EPOCH);
        vm.prank(users[1]);
        with.queue(2 * DUST);

        uint256 amt = with.stop();
        assertEq(amt, 5 * DUST);
    }

    function test_stop_buckets_old() public {
        vm.prank(users[0]);
        with.queue(3 * DUST);

        skip(3 * EPOCH);
        uint256 amt = with.stop();

        assertEq(amt, 0);
        assertEq(with.keep(), 3 * DUST);
    }

    function test_stop_not_auth() public {
        vm.expectRevert();
        vm.prank(users[0]);
        with.stop();
    }

    function test_stop_twice() public {
        with.stop();
        vm.expectRevert("not live");
        with.stop();
    }

    function test_cover() public {
        vm.prank(users[0]);
        with.queue(3 * DUST);
        vm.prank(users[1]);
        with.queue(2 * DUST);

        with.stop();
        stake.stop();
        stake.settle(Stake.State.Cover);

        uint256 keepBefore = with.keep();
        with.cover(INSUREE);

        assertEq(with.dumped(), 0);
        assertEq(with.keep(), keepBefore - 5 * DUST);
    }

    function test_cover_not_stopped() public {
        vm.expectRevert();
        with.cover(INSUREE);
    }

    function test_cover_invalid_state() public {
        with.stop();
        vm.expectRevert("invalid state");
        with.cover(INSUREE);
    }

    function test_cover_not_auth() public {
        with.stop();
        stake.stop();
        stake.settle(Stake.State.Cover);
        vm.expectRevert();
        vm.prank(users[0]);
        with.cover(INSUREE);
    }

    function test_cover_transfers() public {
        vm.prank(users[0]);
        with.queue(3 * DUST);

        with.stop();
        stake.stop();
        stake.settle(Stake.State.Cover);

        uint256 balBefore = token.balanceOf(INSUREE);
        with.cover(INSUREE);
        uint256 balAfter = token.balanceOf(INSUREE);

        assertGt(balAfter, balBefore);
    }

    function test_cover_no_dumped() public {
        with.stop();
        stake.stop();
        stake.settle(Stake.State.Cover);

        uint256 keepBefore = with.keep();
        with.cover(INSUREE);
        assertEq(with.dumped(), 0);
        assertEq(with.keep(), keepBefore);
    }

    function test_unlock_after_cover() public {
        address usr = users[0];
        vm.prank(usr);
        uint256 i = with.queue(DUST);

        skip(EPOCH);
        with.stop();
        assertGt(with.dumped(), 0);

        stake.stop();
        stake.settle(Stake.State.Cover);
        with.cover(INSUREE);
        assertEq(with.dumped(), 0);

        skip(EPOCH);

        vm.expectRevert("dumped");
        vm.prank(usr);
        with.unlock(i);
    }

    function test_refill() public {
        vm.prank(users[0]);
        with.queue(3 * DUST);
        vm.prank(users[1]);
        with.queue(2 * DUST);

        uint256 amt = with.stop();
        assertEq(amt, 5 * DUST);
        assertEq(with.dumped(), 5 * DUST);
        assertEq(with.keep(), 5 * DUST);

        stake.stop();
        stake.settle(Stake.State.Exit);
        with.refill();

        assertEq(with.dumped(), 0);
        assertEq(with.keep(), 5 * DUST);
    }

    function test_refill_no_dumped() public {
        with.stop();
        assertEq(with.dumped(), 0);

        stake.stop();
        stake.settle(Stake.State.Exit);
        with.refill();
        assertEq(with.dumped(), 0);
        assertEq(with.keep(), 0);
    }

    function test_refill_not_stopped() public {
        vm.expectRevert();
        with.refill();
    }

    function test_refill_not_auth() public {
        with.stop();
        stake.stop();
        stake.settle(Stake.State.Exit);
        vm.expectRevert();
        vm.prank(users[0]);
        with.refill();
    }

    function test_refill_invalid_state() public {
        with.stop();
        vm.expectRevert("invalid state");
        with.refill();
    }

    function test_unlock_after_refill() public {
        address usr = users[0];
        vm.prank(usr);
        uint256 i = with.queue(DUST);

        skip(EPOCH);
        with.stop();
        assertGt(with.dumped(), 0);

        stake.stop();
        stake.settle(Stake.State.Exit);
        with.refill();
        assertEq(with.dumped(), 0);

        uint256 balBefore = token.balanceOf(usr);
        vm.prank(usr);
        with.unlock(i);
        assertEq(token.balanceOf(usr), balBefore + DUST);
    }

    function test_recover() public {
        token.mint(address(with), 5 * 1e18);

        vm.prank(users[0]);
        with.queue(DUST);

        uint256 balBefore = token.balanceOf(address(this));
        with.recover(address(token));
        uint256 balAfter = token.balanceOf(address(this));

        assertEq(balAfter - balBefore, 5 * 1e18);
    }

    function test_recover_not_auth() public {
        vm.expectRevert();
        vm.prank(users[0]);
        with.recover(address(token));
    }
}
