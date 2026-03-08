// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

interface IStake {
    enum State {
        Live,
        Stopped,
        Cover,
        Exit
    }

    function state() external view returns (State);
    function token() external view returns (address);
    function deposit(uint256 amt) external;
    function withdraw(address usr, address dst, uint256 amt) external;
    function stop() external;
    function cover(address dst, uint256 amt) external returns (uint256);
}
