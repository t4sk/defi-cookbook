// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {IStake} from "./lib/IStake.sol";
import {IWithdrawDelay} from "./lib/IWithdrawDelay.sol";
import {Auth} from "./lib/Auth.sol";

contract Stop is Auth {
    event Stop();

    IERC20 public immutable token;
    IStake public immutable stake;
    IWithdrawDelay public immutable withdrawDelay;

    // TODO: use create2 + stop inside constructor?
    constructor(address _stake, address _withdrawDelay) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        withdrawDelay = IWithdrawDelay(_withdrawDelay);
        token.approve(address(stake), type(uint256).max);
    }

    function stop() external auth {
        withdrawDelay.dump();
        stake.stop();
        emit Stop();
    }
}
