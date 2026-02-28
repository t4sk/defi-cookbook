// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Test} from "forge-std/Test.sol";
import {Auth} from "@src/insurance/lib/Auth.sol";

contract AuthTest is Test {
    Auth auth;

    function setUp() public {
        auth = new Auth();
    }

    function test_constructor() public {
        assertTrue(auth.auths(address(this)));
    }

    function test_allow() public {
        address usr = address(1);
        auth.allow(usr);
        assertTrue(auth.auths(usr));
    }

    function test_deny() public {
        address usr = address(1);
        auth.allow(usr);

        auth.deny(usr);
        assertFalse(auth.auths(usr));
    }

    function test_allow_reverts_if_not_auth() public {
        address usr = address(1);
        vm.prank(usr);
        vm.expectRevert("not auth");
        auth.allow(usr);
    }

    function test_deny_reverts_if_not_auth() public {
        address usr = address(1);
        vm.prank(usr);
        vm.expectRevert("not auth");
        auth.deny(usr);
    }
}
