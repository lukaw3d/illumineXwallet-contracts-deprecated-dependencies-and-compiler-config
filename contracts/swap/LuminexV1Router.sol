// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import '../interfaces/ILuminexRouterV1.sol';
import "../interfaces/ILuminexV1Factory.sol";
import '../libraries/LuminexLibrary.sol';
import '../interfaces/IWROSE.sol';
import './LuminexV1Pair.sol';

contract LuminexRouterV1 is ILuminexRouterV1 {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address public immutable override factory;
    address public immutable override WROSE;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'LuminexRouterV1: EXPIRED');
        _;
    }

    constructor(address _factory, address _WROSE) {
        factory = _factory;
        WROSE = _WROSE;
    }

    function safeTransferROSE(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }

    receive() external payable {
        assert(msg.sender == WROSE); // only accept ROSE via fallback from the WROSE contract
    }

    function precalculateAmounts(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) public view override returns (uint amountA, uint amountB) {
        (uint reserveA, uint reserveB) = LuminexV1Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = LuminexV1Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'LuminexV1Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = LuminexV1Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'LuminexV1Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (ILuminexV1Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            ILuminexV1Factory(factory).createPair(tokenA, tokenB);
        }
        
        return precalculateAmounts(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
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
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = LuminexV1Library.pairFor(factory, tokenA, tokenB);
        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, pair, amountA);
        SafeERC20.safeTransferFrom(IERC20(tokenB), msg.sender, pair, amountB);
        liquidity = ILuminexV1Pair(pair).mint(to);
    }
    
    function addLiquidityROSE(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountROSE, uint liquidity) {
        (amountToken, amountROSE) = _addLiquidity(
            token,
            WROSE,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountROSEMin
        );
        address pair = LuminexV1Library.pairFor(factory, token, WROSE);
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
        IWROSE(WROSE).deposit{value: amountROSE}();
        assert(IWROSE(WROSE).transfer(pair, amountROSE));
        liquidity = ILuminexV1Pair(pair).mint(to);
        // refund dust ROSE, if any
        if (msg.value > amountROSE) safeTransferROSE(msg.sender, msg.value - amountROSE);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = LuminexV1Library.pairFor(factory, tokenA, tokenB);
        LuminexV1Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = ILuminexV1Pair(pair).burn(to);
        (address token0,) = LuminexV1Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'LuminexV1Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'LuminexV1Router: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityROSE(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountROSE) {
        (amountToken, amountROSE) = removeLiquidity(
            token,
            WROSE,
            liquidity,
            amountTokenMin,
            amountROSEMin,
            address(this),
            deadline
        );
        IERC20(token).safeTransfer(to, amountToken);
        IWROSE(WROSE).withdraw(amountROSE);
        safeTransferROSE(to, amountROSE);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityROSESupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountROSE) {
        (, amountROSE) = removeLiquidity(
            token,
            WROSE,
            liquidity,
            amountTokenMin,
            amountROSEMin,
            address(this),
            deadline
        );
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
        IWROSE(WROSE).withdraw(amountROSE);
        safeTransferROSE(to, amountROSE);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = LuminexV1Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? LuminexV1Library.pairFor(factory, output, path[i + 2]) : _to;
            ILuminexV1Pair(LuminexV1Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = LuminexV1Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'LuminexV1Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IERC20(path[0]).safeTransferFrom(
            msg.sender, LuminexV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = LuminexV1Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'LuminexV1Router: EXCESSIVE_INPUT_AMOUNT');
        IERC20(path[0]).safeTransferFrom(
            msg.sender, LuminexV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactROSEForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WROSE, 'LuminexV1Router: INVALID_PATH');
        amounts = LuminexV1Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'LuminexV1Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWROSE(WROSE).deposit{value: amounts[0]}();
        assert(IWROSE(WROSE).transfer(LuminexV1Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactROSE(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WROSE, 'LuminexV1Router: INVALID_PATH');
        amounts = LuminexV1Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'LuminexV1Router: EXCESSIVE_INPUT_AMOUNT');
        IERC20(path[0]).safeTransferFrom(
            msg.sender, LuminexV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWROSE(WROSE).withdraw(amounts[amounts.length - 1]);
        safeTransferROSE(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForROSE(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WROSE, 'LuminexV1Router: INVALID_PATH');
        amounts = LuminexV1Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'LuminexV1Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IERC20(path[0]).safeTransferFrom(
             msg.sender, LuminexV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWROSE(WROSE).withdraw(amounts[amounts.length - 1]);
        safeTransferROSE(to, amounts[amounts.length - 1]);
    }
    function swapROSEForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WROSE, 'LuminexV1Router: INVALID_PATH');
        amounts = LuminexV1Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'LuminexV1Router: EXCESSIVE_INPUT_AMOUNT');
        IWROSE(WROSE).deposit{value: amounts[0]}();
        assert(IWROSE(WROSE).transfer(LuminexV1Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust ROSE, if any
        if (msg.value > amounts[0]) safeTransferROSE(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = LuminexV1Library.sortTokens(input, output);
            ILuminexV1Pair pair = ILuminexV1Pair(LuminexV1Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = LuminexV1Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? LuminexV1Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        IERC20(path[0]).safeTransferFrom(
            msg.sender, LuminexV1Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'LuminexV1Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactROSEForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WROSE, 'LuminexV1Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWROSE(WROSE).deposit{value: amountIn}();
        assert(IWROSE(WROSE).transfer(LuminexV1Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'LuminexV1Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForROSESupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WROSE, 'LuminexV1Router: INVALID_PATH');
        IERC20(path[0]).safeTransferFrom(
            msg.sender, LuminexV1Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WROSE).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'LuminexV1Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWROSE(WROSE).withdraw(amountOut);
        safeTransferROSE(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return LuminexV1Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return LuminexV1Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return LuminexV1Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return LuminexV1Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return LuminexV1Library.getAmountsIn(factory, amountOut, path);
    }
}
