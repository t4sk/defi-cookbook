// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

interface IWithdrawDelay {
    function dumped() external returns (uint256);
    function dump() external returns (uint256);
    function refill() external;
}

