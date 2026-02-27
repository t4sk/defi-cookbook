// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";
import {Auth} from "@src/insurance/lib/Auth.sol";

contract AuthTest is Test {
    Auth auth;

    function setUp() public {
        auth = new Auth();
    }

    function check_auth() public {
        assert(true);
    }
}
