// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

contract Auth {
    mapping(address => bool) public auths;

    modifier auth() {
        require(auths[msg.sender], "not auth");
        _;
    }

    constructor() {
        auths[msg.sender] = true;
    }

    function allow(address usr) external auth {
        auths[usr] = true;
    }

    function deny(address usr) external auth {
        auths[usr] = false;
    }
}
