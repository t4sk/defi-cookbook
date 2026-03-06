// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {IStake} from "./lib/IStake.sol";
import {IWithdrawDelay} from "./lib/IWithdrawDelay.sol";
import {Auth} from "./lib/Auth.sol";

contract Stop is Auth {
    event Stop();
    event Cover(address dst, uint256 amt);
    event Refill();

    IERC20 public immutable token;
    IStake public immutable stake;
    IWithdrawDelay public immutable withdrawDelay;

    constructor(address _stake, address _withdrawDelay) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        withdrawDelay = IWithdrawDelay(_withdrawDelay);
        // Transfer when cover() is called
        token.approve(address(stake), type(uint256).max);
        // Transfer when refill() is called
        token.approve(address(withdrawDelay), type(uint256).max);
    }

    function stop() external auth {
        withdrawDelay.dump();
        stake.stop();
        emit Stop();
    }

    function cover(address dst) external auth {
        require(dst != address(0), "dst = 0");
        uint256 bal = token.balanceOf(address(this));
        stake.cover(dst, bal);
        emit Cover(dst, bal);
    }

    function refill() external auth {
        // 3 = State.Exit
        require(stake.state() == 3, "not exit");
        uint256 bal = token.balanceOf(address(this));
        require(bal >= withdrawDelay.dumped());
        withdrawDelay.refill();
        emit Refill();
    }
}
