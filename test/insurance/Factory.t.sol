// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Factory} from "@src/insurance/Factory.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {DepositDelay} from "@src/insurance/DepositDelay.sol";
import {WithdrawDelay} from "@src/insurance/WithdrawDelay.sol";
import {Stop} from "@src/insurance/Stop.sol";
import {Auth} from "@src/insurance/lib/Auth.sol";

contract FactoryTest is Test {
    ERC20 token;
    Factory factory;

    uint256 constant DUR = 30 * 24 * 3600;
    uint256 constant DUST = 1e18;
    uint256 constant DELAY = 1 days;
    uint256 constant EPOCH = 1 days;
    address constant INSUREE = address(10);

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        factory = new Factory();
    }

    function test_create() public {
        (address s, address d, address w, address st) =
            factory.create(address(token), DUR, INSUREE, DUST, DELAY, EPOCH);

        Stake stake = Stake(s);
        DepositDelay dep = DepositDelay(d);
        WithdrawDelay with = WithdrawDelay(w);
        Stop stop = Stop(st);

        assertEq(address(stake.token()), address(token));
        assertEq(stake.dur(), DUR);
        assertEq(stake.insuree(), INSUREE);
        assertEq(stake.dust(), DUST);
        assertEq(uint256(stake.state()), uint256(Stake.State.Live));

        assertEq(address(dep.token()), address(token));
        assertEq(address(dep.stake()), s);
        assertEq(dep.DELAY(), DELAY);

        assertEq(address(with.token()), address(token));
        assertEq(address(with.stake()), s);
        assertEq(with.EPOCH(), EPOCH);

        assertEq(address(stop.token()), address(token));
        assertEq(address(stop.stake()), s);
        assertEq(address(stop.withdrawDelay()), w);

        assertTrue(stake.auths(address(this)));
        assertTrue(dep.auths(address(this)));
        assertTrue(with.auths(address(this)));
        assertTrue(stop.auths(address(this)));

        assertFalse(stake.auths(address(factory)));
        assertFalse(dep.auths(address(factory)));
        assertFalse(with.auths(address(factory)));
        assertFalse(stop.auths(address(factory)));

        assertTrue(stake.auths(d));
        assertTrue(stake.auths(w));
        assertTrue(stake.auths(st));
        assertTrue(with.auths(st));
    }

    function test_create_token_zero() public {
        vm.expectRevert("token = 0");
        factory.create(address(0), DUR, INSUREE, DUST, DELAY, EPOCH);
    }

    function test_create_insuree_zero() public {
        vm.expectRevert("insuree = 0");
        factory.create(address(token), DUR, address(0), DUST, DELAY, EPOCH);
    }

    function test_create_dur_zero() public {
        vm.expectRevert("dur = 0");
        factory.create(address(token), 0, INSUREE, DUST, DELAY, EPOCH);
    }

    function test_create_epoch_zero() public {
        vm.expectRevert("epoch = 0");
        factory.create(address(token), DUR, INSUREE, DUST, DELAY, 0);
    }

    function test_create_dust_too_small() public {
        vm.expectRevert("dust / dur = 0");
        factory.create(address(token), DUR, INSUREE, 1, DELAY, EPOCH);
    }
}
