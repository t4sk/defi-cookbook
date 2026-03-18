// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Script, console} from "forge-std/Script.sol";
import {Factory} from "../src/insurance/Factory.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast();
        Factory factory = new Factory();
        console.log("addr:", address(factory));
        vm.stopBroadcast();
    }
}
