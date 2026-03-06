// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {DepositDelay} from "@src/insurance/DepositDelay.sol";

contract DepositDelayTest is Test {
    ERC20 token;
    Stake stake;
    DepositDelay dep;

    uint256 constant DUR = 30 * 24 * 3600;
    uint256 constant DUST = 1e18;
    uint256 constant DELAY = 1 days;
    address constant INSUREE = address(10);
    address[] users = [address(100), address(101), address(102)];

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        stake = new Stake(address(token), DUR, INSUREE, DUST);
        dep = new DepositDelay(address(stake), DELAY);

        stake.allow(address(dep));

        token.mint(INSUREE, 1e18 * DUR);
        vm.prank(INSUREE);
        token.approve(address(stake), type(uint256).max);
        vm.prank(INSUREE);
        stake.inc(1e18 * DUR);

        for (uint256 i = 0; i < users.length; i++) {
            token.mint(users[i], 100 * 1e18);
            vm.prank(users[i]);
            token.approve(address(dep), type(uint256).max);
        }
    }

    function test_constructor() public view {
        assertEq(address(dep.token()), address(token));
        assertEq(address(dep.stake()), address(stake));
        assertEq(dep.DELAY(), DELAY);
        assertEq(dep.keep(), 0);
    }

    function test_queue() public {
        address usr = users[0];
        uint256 amt = DUST;

        vm.prank(usr);
        uint256 i = dep.queue(amt);

        assertEq(i, 0);
        assertEq(dep.counts(usr), 1);
        assertEq(dep.keep(), amt);
        (uint256 lockAmt, uint256 lockExp) = dep.locks(usr, i);
        assertEq(lockAmt, amt);
        assertEq(lockExp, block.timestamp + DELAY);
        assertEq(token.balanceOf(usr), 100 * 1e18 - amt);
    }

    function test_queue_multiple() public {
        address usr = users[0];

        vm.prank(usr);
        uint256 i0 = dep.queue(DUST);
        vm.prank(usr);
        uint256 i1 = dep.queue(2 * DUST);

        assertEq(i0, 0);
        assertEq(i1, 1);
        assertEq(dep.counts(usr), 2);
        assertEq(dep.keep(), 3 * DUST);

        (uint256 amt0,) = dep.locks(usr, 0);
        (uint256 amt1,) = dep.locks(usr, 1);
        assertEq(amt0, DUST);
        assertEq(amt1, 2 * DUST);
    }

    function test_queue_multiple_users() public {
        vm.prank(users[0]);
        dep.queue(DUST);
        vm.prank(users[1]);
        dep.queue(2 * DUST);

        assertEq(dep.counts(users[0]), 1);
        assertEq(dep.counts(users[1]), 1);
        assertEq(dep.keep(), 3 * DUST);
    }

    function test_queue_stopped() public {
        stake.stop();

        vm.expectRevert("stopped");
        vm.prank(users[0]);
        dep.queue(DUST);
    }

    function test_deposit() public {
        address usr = users[0];
        uint256 amt = DUST;

        vm.prank(usr);
        uint256 i = dep.queue(amt);

        skip(DELAY);

        vm.prank(usr);
        dep.deposit(i);

        assertEq(dep.keep(), 0);
        assertEq(stake.total(), amt);
        assertEq(stake.shares(usr), amt);
        (uint256 lockAmt,) = dep.locks(usr, i);
        assertEq(lockAmt, 0);
    }

    function test_deposit_not_expired() public {
        address usr = users[0];

        vm.prank(usr);
        uint256 i = dep.queue(DUST);

        skip(DELAY - 1);

        vm.expectRevert("lock not expired");
        vm.prank(usr);
        dep.deposit(i);
    }

    function test_deposit_no_lock() public {
        vm.expectRevert("lock amt = 0");
        vm.prank(users[0]);
        dep.deposit(0);
    }

    function test_deposit_already_deposited() public {
        address usr = users[0];

        vm.prank(usr);
        uint256 i = dep.queue(DUST);
        skip(DELAY);

        vm.prank(usr);
        dep.deposit(i);

        vm.expectRevert("lock amt = 0");
        vm.prank(usr);
        dep.deposit(i);
    }

    function test_cancel() public {
        address usr = users[0];
        uint256 amt = DUST;
        uint256 balBefore = token.balanceOf(usr);

        vm.prank(usr);
        uint256 i = dep.queue(amt);

        vm.prank(usr);
        dep.cancel(i);

        assertEq(dep.keep(), 0);
        assertEq(token.balanceOf(usr), balBefore);
        (uint256 lockAmt,) = dep.locks(usr, i);
        assertEq(lockAmt, 0);
    }

    function test_cancel_after_delay() public {
        address usr = users[0];
        uint256 balBefore = token.balanceOf(usr);

        vm.prank(usr);
        uint256 i = dep.queue(DUST);
        skip(DELAY);

        vm.prank(usr);
        dep.cancel(i);

        assertEq(token.balanceOf(usr), balBefore);
    }

    function test_cancel_no_lock() public {
        vm.expectRevert("lock amt = 0");
        vm.prank(users[0]);
        dep.cancel(0);
    }

    function test_cancel_already_cancelled() public {
        address usr = users[0];

        vm.prank(usr);
        uint256 i = dep.queue(DUST);

        vm.prank(usr);
        dep.cancel(i);

        vm.expectRevert("lock amt = 0");
        vm.prank(usr);
        dep.cancel(i);
    }

    function test_recover() public {
        token.mint(address(dep), 5 * 1e18);

        vm.prank(users[0]);
        dep.queue(DUST);

        uint256 balBefore = token.balanceOf(address(this));
        dep.recover(address(token));
        uint256 balAfter = token.balanceOf(address(this));

        assertEq(balAfter - balBefore, 5 * 1e18);
    }

    function test_recover_not_auth() public {
        vm.expectRevert("not auth");
        vm.prank(users[0]);
        dep.recover(address(token));
    }
}
