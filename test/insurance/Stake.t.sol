// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test, console} from "forge-std/Test.sol";
import {TestHelper} from "../TestHelper.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Stake} from "@src/insurance/Stake.sol";

contract StakeTest is Test {
    TestHelper helper;
    ERC20 token;
    Stake stake;

    uint256 constant DUR = 30 * 24 * 3600;
    uint256 constant DUST = 1e18;
    address constant INSUREE = address(10);
    address constant COVER = address(11);
    address[] users = [address(100), address(101), address(102)];

    function setUp() public {
        helper = new TestHelper();
        token = new ERC20("test", "TEST", 18);
        stake = new Stake(address(token), DUR, INSUREE, DUST);

        token.mint(address(this), 1000 * 1e18);
        token.approve(address(stake), type(uint256).max);

        token.mint(INSUREE, 100 * 1e18 * DUR);
        vm.prank(INSUREE);
        token.approve(address(stake), type(uint256).max);
        vm.prank(INSUREE);
        stake.inc(1e18 * DUR);

        token.mint(COVER, 100 * 1e18);
        token.approve(COVER, type(uint256).max);
    }

    function test_constructor() public {
        assertTrue(stake.auths(address(this)));
        assertEq(address(stake.token()), address(token));
        assertEq(stake.last(), block.timestamp);
        assertEq(stake.exp(), block.timestamp + DUR);
        assertEq(stake.dur(), DUR);
        assertEq(uint256(stake.state()), uint256(Stake.State.Live));
        assertEq(stake.insuree(), INSUREE);
        assertEq(stake.dust(), DUST);
        assertEq(stake.total(), 0);
        assertEq(stake.shares(address(stake)), 1);
        assertEq(stake.stopped(), false);
    }

    function test_deposit() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);
        assertEq(stake.total(), amt);
        assertEq(stake.shares(usr), amt);
    }

    function test_deposit_not_auth() public {
        vm.expectRevert(bytes("not auth"));
        vm.prank(users[0]);
        stake.deposit(users[0], DUST);
    }

    function test_deposit_not_live() public {
        stake.stop();
        vm.expectRevert(bytes("not live"));
        stake.deposit(users[0], DUST);
    }

    function test_deposit_expired() public {
        vm.warp(stake.exp());
        vm.expectRevert(bytes("expired"));
        stake.deposit(users[0], DUST);
    }

    function test_deposit_invalid_usr() public {
        vm.expectRevert(bytes("invalid usr"));
        stake.deposit(address(stake), DUST);
    }

    function test_deposit_dust() public {
        vm.expectRevert(bytes("dust"));
        stake.deposit(users[0], DUST - 1);
    }

    function test_withdraw() public {
        address usr = users[0];
        address dst = users[1];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        stake.withdraw(usr, dst, amt);
        assertEq(stake.total(), 0);
        assertEq(stake.shares(usr), 0);
        assertEq(token.balanceOf(dst), amt);
    }

    function test_withdraw_not_auth() public {
        address usr = users[0];
        address dst = users[1];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        vm.expectRevert(bytes("not auth"));
        vm.prank(usr);
        stake.withdraw(usr, dst, amt);
    }

    function test_withdraw_not_live() public {
        address usr = users[0];
        address dst = users[1];
        uint256 amt = DUST;
        stake.deposit(usr, amt);
        stake.stop();

        vm.expectRevert(bytes("not live"));
        stake.withdraw(usr, dst, amt);
    }

    function test_withdraw_expired() public {
        address usr = users[0];
        address dst = users[1];
        uint256 amt = DUST;
        stake.deposit(usr, amt);
        vm.warp(stake.exp());

        vm.expectRevert(bytes("expired"));
        stake.withdraw(usr, dst, amt);
    }

    function test_withdraw_invalid_usr() public {
        address dst = users[1];
        uint256 amt = DUST;
        stake.deposit(users[0], amt);

        vm.expectRevert(bytes("invalid usr"));
        stake.withdraw(address(stake), dst, amt);
    }

    function test_withdraw_dust() public {
        address usr = users[0];
        address dst = users[1];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        vm.expectRevert(bytes("dust"));
        stake.withdraw(usr, dst, DUST - 1);
    }

    function test_take() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        vm.prank(usr);
        assertEq(stake.take(), 0);

        vm.warp(stake.exp());
        vm.prank(usr);
        assertGt(stake.take(), 0);

        vm.warp(stake.exp() + 1000);
        vm.prank(usr);
        assertEq(stake.take(), 0);
    }

    function test_take_non_staker() public {
        address usr = users[0];

        vm.prank(usr);
        assertEq(stake.take(), 0);

        vm.prank(usr);
        assertEq(stake.take(), 0);

        vm.warp(stake.exp());
        vm.prank(usr);
        assertEq(stake.take(), 0);

        vm.warp(stake.exp() + 1000);
        vm.prank(usr);
        assertEq(stake.take(), 0);
    }

    function test_restake() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        skip(DUR / 2);

        vm.prank(usr);
        uint256 reward = stake.restake();

        assertGt(reward, 0);
        assertEq(stake.rewards(usr), 0);
        assertGt(stake.paid(), 0);
        assertEq(stake.shares(usr), amt + reward);
    }

    function test_restake_not_live() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        skip(DUR / 2);
        stake.stop();

        vm.expectRevert(bytes("not live"));
        vm.prank(usr);
        stake.restake();
    }

    function test_restake_expired() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        vm.warp(stake.exp());

        vm.expectRevert(bytes("expired"));
        vm.prank(usr);
        stake.restake();
    }

    function test_refund() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        vm.prank(INSUREE);
        stake.refund();
        assertEq(stake.paid(), 0);

        skip(DUR / 2);
        vm.prank(INSUREE);
        stake.refund();
        assertGe(stake.paid(), stake.topped() / 2 - DUST);
        assertLe(stake.paid(), stake.topped() / 2);

        vm.warp(stake.exp());
        vm.prank(INSUREE);
        stake.refund();
        assertLe(stake.paid(), stake.topped());

        vm.warp(stake.exp() + 1000);
        vm.prank(INSUREE);
        stake.refund();
        assertLe(stake.paid(), stake.topped());
    }

    function test_refund_no_staker() public {
        vm.prank(INSUREE);
        stake.refund();
        assertEq(stake.paid(), 0);

        skip(DUR / 2);
        vm.prank(INSUREE);
        stake.refund();
        assertApproxEqAbs(stake.paid(), stake.topped() / 2, 1);

        vm.warp(stake.exp());
        vm.prank(INSUREE);
        stake.refund();
        assertApproxEqAbs(stake.paid(), stake.topped(), 1);

        vm.warp(stake.exp() + 1000);
        vm.prank(INSUREE);
        stake.refund();
        assertApproxEqAbs(stake.paid(), stake.topped(), 1);
    }

    function test_refund_keep() public {
        skip(DUR / 2);
        stake.stop();

        vm.prank(INSUREE);
        stake.refund();
        // Refund = topped / 2 + keep
        assertApproxEqAbs(stake.paid(), stake.topped(), 1);

        // Refund again
        vm.prank(INSUREE);
        stake.refund();
        assertApproxEqAbs(stake.paid(), stake.topped(), 1);
    }

    function test_refund_not_auth() public {
        vm.expectRevert("not insuree");
        stake.refund();
    }

    function test_inc() public {
        helper.set("rate before", stake.rate());
        stake.inc(100 * 1e18);
        helper.set("rate after", stake.rate());

        assertGt(helper.get("rate after"), helper.get("rate before"));
    }

    function test_inc_not_live() public {
        stake.stop();
        vm.expectRevert("not live");
        stake.inc(100 * 1e18);
    }

    function test_inc_expired() public {
        vm.warp(stake.exp());
        vm.expectRevert("expired");
        stake.inc(100 * 1e18);
    }

    function test_inc_dust() public {
        vm.expectRevert("delta rate = 0");
        stake.inc(100);
    }

    function test_roll() public {
        uint256 r = 100;
        uint256 amt = r * DUR;

        skip(DUR / 2 + 1);
        vm.prank(INSUREE);
        stake.roll(r);

        assertEq(stake.nextRate(), r);
        assertEq(stake.next(), stake.exp() - DUR);
        assertEq(stake.exp(), stake.next() + DUR);

        vm.expectRevert("rolled");
        vm.prank(INSUREE);
        stake.roll(0);
    }

    function test_roll_not_auth() public {
        vm.expectRevert("not insuree");
        stake.roll(0);
    }

    function test_roll_not_live() public {
        stake.stop();
        vm.expectRevert("not live");
        vm.prank(INSUREE);
        stake.roll(0);
    }

    function test_roll_expired() public {
        vm.warp(stake.exp());
        vm.expectRevert("expired");
        vm.prank(INSUREE);
        stake.roll(0);
    }

    function test_roll_too_early() public {
        skip(DUR / 2 - 1);
        vm.expectRevert("too early");
        vm.prank(INSUREE);
        stake.roll(0);
    }

    function test_stop() public {
        stake.stop();
        assertTrue(stake.stopped());
        assertApproxEqAbs(stake.keep(), stake.topped(), 1);
    }

    function test_stop_keep() public {
        skip(DUR / 2);
        stake.stop();
        assertApproxEqAbs(stake.keep(), stake.topped(), 1);
    }

    function test_stop_keep_zero() public {
        vm.warp(stake.exp() - 1);
        stake.stop();
        assertApproxEqAbs(stake.keep(), stake.topped(), 1);
    }

    function test_stop_not_auth() public {
        vm.expectRevert("not auth");
        vm.prank(users[0]);
        stake.stop();
    }

    function test_stop_not_live() public {
        stake.stop();
        vm.expectRevert("not live");
        stake.stop();
    }

    function test_stop_expired() public {
        vm.warp(stake.exp());
        vm.expectRevert("expired");
        stake.stop();
    }

    function test_settle() public {
        stake.stop();
        stake.settle(Stake.State.Cover);
        assertEq(uint256(stake.state()), uint256(Stake.State.Cover));

        // Cannot settle again
        vm.expectRevert("not stopped");
        stake.settle(Stake.State.Cover);
    }

    function test_settle_auth() public {
        vm.expectRevert("not auth");
        vm.prank(users[0]);
        stake.stop();
    }

    function test_settle_not_stopped() public {
        vm.expectRevert("not stopped");
        stake.settle(Stake.State.Cover);
    }

    function test_settle_invalid_next_state() public {
        stake.stop();
        vm.expectRevert("invalid next state");
        stake.settle(Stake.State.Stopped);
    }

    function test_cover() public {
        stake.stop();
        stake.settle(Stake.State.Cover);
        stake.cover(COVER, 0, INSUREE);
        assertEq(stake.total(), 0);
    }

    function test_cover_not_auth() public {
        stake.stop();
        stake.settle(Stake.State.Cover);
        vm.expectRevert("not auth");
        vm.prank(users[0]);
        stake.cover(COVER, 0, INSUREE);
    }

    function test_cover_not_cover() public {
        vm.expectRevert("invalid state");
        stake.cover(COVER, 0, INSUREE);
    }

    function test_exit() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        skip(DUR / 2);
        stake.stop();
        stake.settle(Stake.State.Exit);

        vm.prank(usr);
        uint256 out = stake.exit();
        assertGt(out, amt);
        assertEq(stake.rewards(usr), 0);
        assertEq(stake.shares(usr), 0);

        vm.prank(usr);
        assertEq(stake.exit(), 0);
    }

    function test_exit_expired() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        vm.warp(stake.exp() + 1);

        vm.prank(usr);
        uint256 out = stake.exit();
        assertGt(out, amt);
    }

    function test_exit_non_staker() public {
        vm.warp(stake.exp() + 1);

        vm.prank(users[0]);
        assertEq(stake.exit(), 0);
    }

    function test_recover() public {
        address usr = users[0];
        uint256 amt = DUST;
        stake.deposit(usr, amt);

        skip(DUR / 2);

        vm.prank(usr);
        stake.take();

        vm.prank(INSUREE);
        stake.refund();

        token.transfer(address(stake), 1);

        helper.set("before", token.balanceOf(address(this)));
        stake.recover(address(token));
        helper.set("after", token.balanceOf(address(this)));

        int256 delta = helper.delta("after", "before");
        assertEq(delta, 1);
    }

    function test_recover_not_auth() public {
        vm.expectRevert("not auth");
        vm.prank(users[0]);
        stake.recover(address(token));
    }

    // TODO: test pot
    // TODO: test calc
    // TODO: test sync

    // sync
    // - address(0)
    // - address(this)
    // - staker
    // - not staker
    // - before exp, after exp
    // - next rate

    // TODO: integration - fuzz + sim
    // TODO: invariants
    // - cannot earn rewards beyond exp
    // - Emissions in any single sync interval never exceed total staked.
}
