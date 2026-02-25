// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

interface IWithdrawDelay {
    function lock() external returns (uint256);
}

