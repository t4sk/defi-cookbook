// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.32;

contract TestHelper {
    mapping(string => uint256) public vals;

    function set(string memory key, uint256 val) public {
        vals[key] = val;
    }

    function get(string memory key) public view returns (uint256) {
        return vals[key];
    }

    function delta(string memory key0, string memory key1)
        public
        view
        returns (int256)
    {
        return int256(vals[key0]) - int256(vals[key1]);
    }
}
