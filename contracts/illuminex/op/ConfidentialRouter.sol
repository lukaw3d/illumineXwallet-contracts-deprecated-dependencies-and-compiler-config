// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./SapphireEndpoint.sol";
import '../../interfaces/IWROSE.sol';
import "../../confidentialERC20/PrivateWrapperFactory.sol";

contract ConfidentialRouter {
    using SafeERC20 for IERC20;

    PrivateWrapperFactory public immutable wrapperFactory;
    ILuminexRouterV1 public immutable swapRouter;

    constructor(address payable _wrapperFactory, address payable _illiminexRouter) {
        wrapperFactory = PrivateWrapperFactory(_wrapperFactory);
        swapRouter = ILuminexRouterV1(_illiminexRouter);
    }

    function _removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) private returns (uint amountA, uint amountB) {
        require(wrapperFactory.tokenByWrapper(tokenA) != address(0) && wrapperFactory.tokenByWrapper(tokenB) != address(0), "Invalid wrappers input");

        address _pair = LuminexV1Library.pairFor(swapRouter.factory(), tokenA, tokenB);

        IERC20(_pair).safeTransferFrom(msg.sender, address(this), liquidity);
        IERC20(_pair).safeIncreaseAllowance(address(swapRouter), liquidity);
        (amountA, amountB) = swapRouter.removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, address(this), deadline);

        IERC20(tokenA).safeIncreaseAllowance(address(wrapperFactory), amountA);
        IERC20(tokenB).safeIncreaseAllowance(address(wrapperFactory), amountB);

        wrapperFactory.unwrapERC20(tokenA, amountA, to);
        wrapperFactory.unwrapERC20(tokenB, amountB, to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public returns (uint amountA, uint amountB) {
        return _removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    
    function removeLiquidityROSE(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountROSEMin,
        address payable to,
        uint deadline
    ) public returns (uint amountToken, uint amountROSE) {
        (amountToken, amountROSE) = _removeLiquidity(
            token,
            address(wrapperFactory.wrappers(swapRouter.WROSE())),
            liquidity,
            amountTokenMin,
            amountROSEMin,
            address(this),
            deadline
        );

        IERC20(wrapperFactory.tokenByWrapper(token)).safeTransfer(to, amountToken);
        IWROSE(swapRouter.WROSE()).withdraw(amountROSE);

        to.transfer(amountROSE);
    }

    receive() external payable {}

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
        (amountA, amountB) = swapRouter.precalculateAmounts(
            address(wrapperFactory.wrappers(tokenA)),
            address(wrapperFactory.wrappers(tokenB)),
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        {
            IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
            IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

            {
                IERC20(tokenA).safeIncreaseAllowance(address(wrapperFactory), amountA);
                IERC20(tokenB).safeIncreaseAllowance(address(wrapperFactory), amountB);

                wrapperFactory.wrapERC20(tokenA, amountA, address(this));
                wrapperFactory.wrapERC20(tokenB, amountB, address(this));
            }

            tokenA = address(wrapperFactory.wrappers(tokenA));
            tokenB = address(wrapperFactory.wrappers(tokenB));
        }

        {
            IERC20(tokenA).safeIncreaseAllowance(address(swapRouter), amountA);
            IERC20(tokenB).safeIncreaseAllowance(address(swapRouter), amountB);
        }

        return swapRouter.addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, to, deadline);
    }
    
    function addLiquidityROSE(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountROSE, uint liquidity) {
        (uint amountA, uint amountB) = swapRouter.precalculateAmounts(
            address(wrapperFactory.wrappers(token)),
            address(wrapperFactory.wrappers(swapRouter.WROSE())),
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountROSEMin
        );

        IWROSE(swapRouter.WROSE()).deposit{value: amountB}();
        if (msg.value > amountB) payable(msg.sender).transfer(msg.value - amountB);

        {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amountA);

            {
                IERC20(token).safeIncreaseAllowance(address(wrapperFactory), amountA);
                IERC20(swapRouter.WROSE()).safeIncreaseAllowance(address(wrapperFactory), amountB);

                wrapperFactory.wrapERC20(token, amountA, address(this));
                wrapperFactory.wrapERC20(swapRouter.WROSE(), amountB, address(this));
            }
        }

        {
            address tokenA = address(wrapperFactory.wrappers(token));
            address tokenB = address(wrapperFactory.wrappers(swapRouter.WROSE()));

            IERC20(tokenA).safeIncreaseAllowance(address(swapRouter), amountA);
            IERC20(tokenB).safeIncreaseAllowance(address(swapRouter), amountB);
        }

        return swapRouter.addLiquidity(
            address(wrapperFactory.wrappers(token)),
            address(wrapperFactory.wrappers(swapRouter.WROSE())),
            amountTokenDesired,
            amountB,
            amountTokenMin,
            amountROSEMin,
            to,
            deadline
        );
    }    
}