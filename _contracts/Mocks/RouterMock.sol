// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

/*
import "hardhat/console.sol";
import "../IRouterV2.sol";
import "../Tokens/IBEP20.sol";
import "../Tokens/BEP20.sol";
import "../Libraries/SafeBEP20.sol";

contract RouterMock {
    using SafeBEP20 for IBEP20;

    // Needs to be set up with the proper tokens for transfer them.
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual returns (uint[] memory amounts) {
        IBEP20 token = IBEP20(path[1]);
        token.safeTransfer(to, amountIn);

        amounts = new uint[](1);
        amounts[0] = amountIn;
    }

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        IBEP20 token = IBEP20(path[1]);
        token.safeTransfer(to, amountOutMin);

        amounts = new uint[](1);
        amounts[0] = amountOutMin;
    }

    function getAmountsOut(uint amountIn, address[] memory path)
    public
    view
    virtual
    returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }

    // Returns always 2.5 each token
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        amountA = 1e18;
        amountB = 1e18;
        BEP20(tokenA).transfer(msg.sender, amountA);
        BEP20(tokenB).transfer(msg.sender, amountB);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        amountA = 1e18;
        amountB = 1e18;
    }
}
*/