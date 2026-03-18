// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Script, console} from "forge-std/Script.sol";
import {Token} from "../test/Token.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast();
        Token token = new Token("test", "TEST", 18);
        console.log("addr:", address(token));
        vm.stopBroadcast();
    }
}
