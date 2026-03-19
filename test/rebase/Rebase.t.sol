// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test, console} from "forge-std/Test.sol";
import {RAY} from "@src/lib/Math.sol";
import {Rebase} from "@src/rebase/Rebase.sol";
import {Token} from "../Token.sol";

address constant AUTH = address(1);

contract Handler is Test {
    Token immutable token;
    Rebase immutable rebase;

    address[] public users = [address(10), address(11), address(12)];
    address private user;

    modifier prank(uint256 seed) {
        user = users[seed % users.length];
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    constructor(address _token, address _rebase) {
        token = Token(_token);
        rebase = Rebase(_rebase);

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            token.approve(address(rebase), type(uint256).max);
        }
    }

    function top(address usr, uint256 amt) private {
        uint256 bal = token.balanceOf(usr);
        if (amt > bal) {
            token.mint(usr, amt - bal);
        }
    }

    function warp(uint256 dt) external {
        dt = bound(dt, 0, 3 days);
        vm.warp(block.timestamp + dt);
    }

    function set(uint256 r) external {
        // Capped at 1000% growth in 1 year
        r = bound(r, RAY, RAY + 7.3 * 1e19);
        vm.prank(AUTH);
        rebase.set(r);
    }

    function sync() external {
        rebase.sync();
    }

    function join(uint256 seed, uint256 amt) external prank(seed) {
        amt = bound(amt, 0, 1e9 * 1e18);
        rebase.sync();
        if (amt * RAY / rebase.acc() > 0) {
            top(user, amt);
            rebase.join(amt);
        }
    }

    function exit(uint256 seed, uint256 s) external prank(seed) {
        s = bound(s, 0, rebase.shares(user));
        if (s > 0) {
            rebase.exit(s);
        }
    }

    function transfer(uint256 seed, uint256 s) external prank(seed) {
        s = bound(s, 0, rebase.shares(user));
        if (s > 0) {
            // Use s as random seed
            address dst = users[s % users.length];
            rebase.transfer(dst, s);
        }
    }
}

contract RebaseTest is Test {
    Token token;
    Rebase rebase;
    Handler handler;

    constructor() {
        token = new Token("test", "TEST", 18);
        rebase = new Rebase(address(token));
        handler = new Handler(address(token), address(rebase));

        rebase.allow(AUTH);
        targetContract(address(handler));
    }

    function invariant_bal_ge_sum() public {
        rebase.sync();
        uint256 bal = token.balanceOf(address(rebase));
        uint256 sum = rebase.sum();
        assertGe(bal, sum);
    }

    function invariant_sum_ge_user_bals() public view {
        uint256 tot = 0;
        for (uint256 i = 0; i < 3; i++) {
            tot += rebase.balance(handler.users(i));
        }
        uint256 sum = rebase.sum();
        assertGe(sum, tot);
    }
}
