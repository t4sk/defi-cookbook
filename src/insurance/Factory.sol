// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Stake} from "./Stake.sol";
import {WithdrawDelay} from "./WithdrawDelay.sol";

contract Factory {
    event Create(
        address indexed insuree,
        address indexed token,
        address stake,
        address withdraw
    );

    function create(
        // Payment token
        address token,
        address insuree,
        // Insurance duration
        uint256 dur,
        // Insurance dust
        uint256 dust,
        // Insurance coverage (total staked / premium paid)
        uint256 cov,
        // Min withdraw delay
        uint256 epoch
    ) external returns (address, address) {
        require(token != address(0), "token = 0");
        require(insuree != address(0), "insuree = 0");
        require(dur > 0, "dur = 0");
        require(epoch > 0, "epoch = 0");

        Stake stake = new Stake(token, insuree, dur, dust, cov);
        WithdrawDelay withdraw = new WithdrawDelay(address(stake), epoch);

        stake.allow(address(withdraw));
        stake.allow(msg.sender);
        withdraw.allow(msg.sender);

        stake.deny(address(this));
        withdraw.deny(address(this));

        emit Create(insuree, token, address(stake), address(withdraw));

        return (address(stake), address(withdraw));
    }
}
