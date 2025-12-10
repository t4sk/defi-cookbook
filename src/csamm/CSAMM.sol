// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import {IERC20} from "../lib/IERC20.sol";

// Constant Sum AMM
contract Token {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    function _mint(address dst, uint256 amt) internal {
        balanceOf[dst] += amt;
        totalSupply += amt;
    }

    function _burn(address src, uint256 amt) internal {
        balanceOf[src] -= amt;
        totalSupply -= amt;
    }
}

contract CSAMM is Token {
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    // Multipliers to normalize token decimals to 18
    uint256 public immutable NORM0;
    uint256 public immutable NORM1;
    uint256 public immutable FEE;
    uint256 private constant MAX_FEE = 10000;

    constructor(address _token0, address _token1, uint256 _fee) {
        uint8 dec0 = IERC20(_token0).decimals();
        uint8 dec1 = IERC20(_token1).decimals();

        require(dec0 <= 18, "token0 decimals > 18");
        require(dec1 <= 18, "token1 decimals > 18");

        NORM0 = 10 ** (18 - dec0);
        NORM1 = 10 ** (18 - dec1);

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        require(_fee <= MAX_FEE, "fee > max");
        FEE = _fee;
    }

    function addLiquidity(uint256 amt0, uint256 amt1)
        external
        returns (uint256 shares)
    {
        // Calculate actual amount transferred
        uint256 bal0Before = token0.balanceOf(address(this));
        uint256 bal1Before = token1.balanceOf(address(this));

        token0.transferFrom(msg.sender, address(this), amt0);
        token1.transferFrom(msg.sender, address(this), amt1);

        uint256 bal0After = token0.balanceOf(address(this));
        uint256 bal1After = token1.balanceOf(address(this));

        uint256 delta0 = (bal0After - bal0Before) * NORM0;
        uint256 delta1 = (bal1After - bal1Before) * NORM1;
        // Total liquidity
        uint256 liq = bal0Before * NORM0 + bal1Before * NORM1;

        /*
        a = amount in
        L = total liquidity
        s = shares to mint
        T = total supply

        s should be proportional to increase from L to L + a
        (L + a) / L = (T + s) / T

        s = a * T / L
        */
        if (totalSupply > 0) {
            shares = ((delta0 + delta1) * totalSupply) / liq;
        } else {
            shares = delta0 + delta1;
        }

        require(shares > 0, "shares = 0");
        _mint(msg.sender, shares);
    }

    function removeLiquidity(uint256 shares, uint256 min0, uint256 min1)
        external
        returns (uint256 delta0, uint256 delta1)
    {
        /*
        a = amount out
        L = total liquidity
        s = shares
        T = total supply

        a / L = s / T

        a = L * s / T
        */

        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        delta0 = (bal0 * shares) / totalSupply;
        delta1 = (bal1 * shares) / totalSupply;

        require(delta0 >= min0, "delta0 < min");
        require(delta1 >= min1, "delta1 < min");

        _burn(msg.sender, shares);

        if (delta0 > 0) {
            token0.transfer(msg.sender, delta0);
        }
        if (delta1 > 0) {
            token1.transfer(msg.sender, delta1);
        }
    }

    function swap(bool zeroToOne, uint256 amtIn, uint256 minOut)
        external
        returns (uint256 amtOut)
    {
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            uint256 balIn,
            uint256 normIn,
            uint256 normOut
        ) = zeroToOne
            ? (token0, token1, bal0, NORM0, NORM1)
            : (token1, token0, bal1, NORM1, NORM0);

        tokenIn.transferFrom(msg.sender, address(this), amtIn);
        uint256 deltaIn = tokenIn.balanceOf(address(this)) - balIn;

        // 18 - (18 - decimals out) = decimals out
        amtOut = (deltaIn * normIn) / normOut;
        amtOut = (amtOut * (MAX_FEE - FEE)) / MAX_FEE;

        require(amtOut >= minOut, "out < min");

        tokenOut.transfer(msg.sender, amtOut);
    }
}

