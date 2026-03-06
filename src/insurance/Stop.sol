// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {IStake} from "./lib/IStake.sol";
import {IWithdrawDelay} from "./lib/IWithdrawDelay.sol";
import {Auth} from "./lib/Auth.sol";

contract Stop is Auth {
    using SafeTransfer for IERC20;

    event Stop();
    event Cover(address dst, uint256 amt);
    event Refill();

    IERC20 public immutable token;
    IStake public immutable stake;
    IWithdrawDelay public immutable withdrawDelay;
    uint256 public keep;

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
        keep = withdrawDelay.dump();
        stake.stop();
        emit Stop();
    }

    function cover(address dst) external auth {
        require(dst != address(0), "dst = 0");
        uint256 amt = keep;
        keep = 0;
        stake.cover(dst, amt);
        emit Cover(dst, amt);
    }

    function refill() external auth {
        // 3 = State.Exit
        require(stake.state() == 3, "not exit");
        keep = 0;
        withdrawDelay.refill();
        emit Refill();
    }

    function recover(address _token) external auth {
        if (_token == address(0)) {
            (bool ok,) = msg.sender.call{value: address(this).balance}("");
            require(ok, "send ETH failed");
        } else if (_token == address(token)) {
            uint256 bal = token.balanceOf(address(this));
            token.safeTransfer(msg.sender, bal - keep);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, bal);
        }
    }
}
