// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

interface IWithdrawDelay {
    enum State {
        Live,
        Stopped,
        Covered,
        Refilled
    }

    function state() external view returns (State);
    function dumped() external returns (uint256);
    function dump() external returns (uint256);
    function refill() external;
}

