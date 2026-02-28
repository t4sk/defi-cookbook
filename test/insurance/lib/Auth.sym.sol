// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";
import {Auth} from "@src/insurance/lib/Auth.sol";

// TODO: sim test
contract AuthSymTest is SymTest, Test {
    Auth auth;

    function setUp() public {
        auth = new Auth();
    }

    function check_auth() public {
        // Execute N arbitrary calls
        for (uint256 i = 0; i < 5; i++) {
            // Create fresh symbolic calldata each iteration
            bytes memory data = svm.createCalldata("Auth");

            vm.prank(address(this));
            // Call the target with symbolic selector + args
            (bool success,) = address(auth).call(data);
        }
        assert(auth.auths(address(this)));
    }
}
