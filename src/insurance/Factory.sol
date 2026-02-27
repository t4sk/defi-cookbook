// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

import {Stake} from "./Stake.sol";
import {DepositDelay} from "./DepositDelay.sol";
import {WithdrawDelay} from "./WithdrawDelay.sol";
import {Stop} from "./Stop.sol";

// TODO: events
// TODO: minimal proxy?
contract Factory {
    function create(address token, uint256 dur, uint256 delay, uint256 epoch)
        external
    {
        // TODO: input validations
        Stake stake = new Stake(token, dur);
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
    }
}
