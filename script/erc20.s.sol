// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "../src/lib/ERC20.sol";

// Update these parameters
string constant NAME = "TOKEN";
string constant SYMBOL = "TKN";
uint8 constant DECIMALS = 6;

contract CSAMMScript is Script {
    ERC20 public erc20;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        erc20 = new ERC20(NAME, SYMBOL, DECIMALS);

        vm.stopBroadcast();
    }
}
