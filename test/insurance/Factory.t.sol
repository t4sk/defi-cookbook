// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@src/lib/ERC20.sol";
import {Factory} from "@src/insurance/Factory.sol";
import {Stake} from "@src/insurance/Stake.sol";
import {WithdrawDelay} from "@src/insurance/WithdrawDelay.sol";
import {Auth} from "@src/insurance/lib/Auth.sol";

contract FactoryTest is Test {
    ERC20 token;
    Factory factory;

    uint256 constant DUR = 30 * 24 * 3600;
    uint256 constant DUST = 1e18;
    uint256 constant COV = 1;
    uint256 constant EPOCH = 1 days;
    address constant INSUREE = address(10);

    function setUp() public {
        token = new ERC20("test", "TEST", 18);
        factory = new Factory();
    }

    function test_create() public {
        (address s, address w) =
            factory.create(address(token), INSUREE, DUR, DUST, COV, EPOCH);

        Stake stake = Stake(s);
        WithdrawDelay with = WithdrawDelay(w);

        assertEq(address(stake.token()), address(token));
        assertEq(stake.dur(), DUR);
        assertEq(stake.insuree(), INSUREE);
        assertEq(stake.dust(), DUST);
        assertEq(stake.cov(), COV);
        assertEq(uint256(stake.state()), uint256(Stake.State.Live));

        assertEq(address(with.token()), address(token));
        assertEq(address(with.stake()), s);
        assertEq(with.EPOCH(), EPOCH);

        assertTrue(stake.auths(address(this)));
        assertTrue(with.auths(address(this)));

        assertFalse(stake.auths(address(factory)));
        assertFalse(with.auths(address(factory)));

        assertTrue(stake.auths(w));
    }

    function test_create_token_zero() public {
        vm.expectRevert("token = 0");
        factory.create(address(0), INSUREE, DUR, DUST, COV, EPOCH);
    }

    function test_create_insuree_zero() public {
        vm.expectRevert("insuree = 0");
        factory.create(address(token), address(0), DUR, DUST, COV, EPOCH);
    }

    function test_create_dur_zero() public {
        vm.expectRevert("dur = 0");
        factory.create(address(token), INSUREE, 0, DUST, COV, EPOCH);
    }

    function test_create_epoch_zero() public {
        vm.expectRevert("epoch = 0");
        factory.create(address(token), INSUREE, DUR, DUST, COV, 0);
    }
}
