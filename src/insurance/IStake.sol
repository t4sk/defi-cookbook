// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

interface IStake {
    function token() external view returns (address);
    function deposit(address usr, uint256 amt) external;
    function withdraw(address usr, address dst, uint256 amt) external;
}
