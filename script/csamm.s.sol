// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Script} from "forge-std/Script.sol";
import {CSAMM} from "../src/csamm/CSAMM.sol";

// Update these parameters
address constant token0 = 0x140e1Af0bdd3AcE2D2CbE5B76F1De4A40c340308;
address constant token1 = 0x1964FdC444333cC099c7A908C61e277e9d252269;
uint256 constant fee = 10;

contract CSAMMScript is Script {
    CSAMM public csamm;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        csamm = new CSAMM(token0, token1, fee);

        vm.stopBroadcast();
    }
}
