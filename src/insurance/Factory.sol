// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Stake} from "./Stake.sol";
import {DepositDelay} from "./DepositDelay.sol";
import {WithdrawDelay} from "./WithdrawDelay.sol";
import {Stop} from "./Stop.sol";

contract Factory {
    event Create(
        address indexed insuree,
        address indexed token,
        address stake,
        address deposit,
        address withdraw,
        address stop
    );

    function create(
        address token,
        uint256 dur,
        address insuree,
        uint256 dust,
        uint256 delay,
        uint256 epoch
    ) external returns (address, address, address, address) {
        require(token != address(0), "token = 0");
        require(insuree != address(0), "insuree = 0");
        require(dur > 0, "dur = 0");
        require(dust / dur > 0, "dust / dur = 0");
        require(epoch > 0, "epoch = 0");

        Stake stake = new Stake(token, dur, insuree, dust);
        DepositDelay deposit = new DepositDelay(address(stake), delay);
        WithdrawDelay withdraw = new WithdrawDelay(address(stake), epoch);
        Stop stop = new Stop(address(stake), address(withdraw));

        stake.allow(address(deposit));
        stake.allow(address(withdraw));
        stake.allow(address(stop));
        withdraw.allow(address(stop));

        stake.allow(msg.sender);
        deposit.allow(msg.sender);
        withdraw.allow(msg.sender);
        stop.allow(msg.sender);

        stake.deny(address(this));
        deposit.deny(address(this));
        withdraw.deny(address(this));
        stop.deny(address(this));

        emit Create(
            insuree,
            token,
            address(stake),
            address(deposit),
            address(withdraw),
            address(stop)
        );

        return
            (address(stake), address(deposit), address(withdraw), address(stop));
    }
}
