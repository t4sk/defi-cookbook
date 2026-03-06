// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {DepositDelay} from "@src/insurance/DepositDelay.sol";
import {WithdrawDelay} from "@src/insurance/WithdrawDelay.sol";
import {Stop as StopContract} from "@src/insurance/Stop.sol";

contract StopTest is Test {
    ERC20 token;
    Stake stake;
    DepositDelay dep;
    WithdrawDelay with;
    StopContract stop;

    uint256 constant DUR = 30 * 24 * 3600;
    uint256 constant DUST = 1e18;
    uint256 constant DELAY = 1 days;
    uint256 constant EPOCH = 1 days;
    address constant INSUREE = address(10);
    address[] users = [address(100), address(101), address(102)];

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        stake = new Stake(address(token), DUR, INSUREE, DUST);
        dep = new DepositDelay(address(stake), DELAY);
        with = new WithdrawDelay(address(stake), EPOCH);
        stop = new StopContract(address(stake), address(with));

        // Auth
        stake.allow(address(dep));
        stake.allow(address(with));
        stake.allow(address(stop));
        with.allow(address(stop));

        // Fund and approve for inc
        token.mint(INSUREE, 1e18 * DUR);
        vm.prank(INSUREE);
        token.approve(address(stake), type(uint256).max);
        vm.prank(INSUREE);
        stake.inc(1e18 * DUR);

        // Fund users
        for (uint256 i = 0; i < users.length; i++) {
            token.mint(users[i], 100 * 1e18);
            vm.prank(users[i]);
            token.approve(address(dep), type(uint256).max);
        }
    }

    function test_constructor() public view {
        assertEq(address(stop.token()), address(token));
        assertEq(address(stop.stake()), address(stake));
        assertEq(address(stop.withdrawDelay()), address(with));
    }

    function test_stop() public {
        vm.prank(users[0]);
        uint256 i = dep.queue(DUST);
        skip(DELAY);
        vm.prank(users[0]);
        dep.deposit(i);

        skip(DUR / 4);

        vm.prank(users[0]);
        with.queue(DUST);

        uint256 bal = token.balanceOf(address(with));
        stop.stop();

        assertEq(token.balanceOf(address(stop)), bal);
        assertTrue(stake.stopped());
        assertTrue(with.dumped());
    }

    function test_stop_not_auth() public {
        vm.expectRevert();
        vm.prank(users[0]);
        stop.stop();
    }

    function test_stop_twice() public {
        stop.stop();
        vm.expectRevert();
        stop.stop();
    }
}
