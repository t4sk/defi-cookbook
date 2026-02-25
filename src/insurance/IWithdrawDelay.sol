// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

interface IWithdrawDelay {
    function locked() external view returns (uint256);
}

