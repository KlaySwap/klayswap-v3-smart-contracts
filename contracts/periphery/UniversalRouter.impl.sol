// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "../interfaces/IV2Router.sol";
import "../interfaces/IV2Factory.sol";
import "../interfaces/IExchange.sol";
import "../core/interfaces/IUniswapV3Pool.sol";
import "./interfaces/IV3Estimator.sol";
import "./interfaces/ISwapRouter.sol";
import './interfaces/external/IWETH9.sol';
import "./libraries/TransferHelper.sol";

contract UniversalRouterImpl {

    struct SwapParams {
        address to;
        address[] path;
        address[] pool;
        uint256 deadline;
    }

    enum PoolType {
        INVALID,
        GENERAL,
        V3
    }

    address public v2Factory;
    address public v3Factory;
    address public estimator;
    address public v2Router;
    address public v3Router;
    address public WETH;

    bool public entered;

    address public withdrawer;

    constructor() {}

    function _initialize(
        address _v2Factory,
        address _v3Factory,
        address _v2Router,
        address _v3Router,
        address _estimator,
        address _WETH
    ) public {
        require(v2Factory == address(0));
        v2Factory = _v2Factory;
        v3Factory = _v3Factory;
        estimator = _estimator;
        v2Router = _v2Router;
        v3Router = _v3Router;
        WETH = _WETH;
    }

    modifier nonReentrant {
        require(!entered, "ReentrancyGuard: reentrant call");

        entered = true;
        _;
        entered = false;
    }

    modifier onlyFactories {
        require(msg.sender == v2Factory || msg.sender == v3Factory);

        _;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'UniversalRouter: EXPIRED');
        _;
    }

    function version() public pure returns (string memory) {
        return "UniversalRouterImpl20240528";
    }

    function poolExist(address pool) private view returns (uint256) {
        if (IV2Factory(v3Factory).poolExist(pool)) {
            return uint256(PoolType.V3);
        } else if (IV2Factory(v2Factory).poolExist(pool)) {
            return uint256(PoolType.GENERAL);
        }
        return uint256(PoolType.INVALID);
    }

    function inCaseTokensGetStuck(address token, uint256 amount, address to) external {
        require(msg.sender == withdrawer);
        if(token == address(0)){
            require(address(this).balance >= amount);
            TransferHelper.safeTransferETH(to, amount);
        }
        else {
            require(IERC20(token).balanceOf(address(this)) >= amount);
            TransferHelper.safeTransfer(token, to, amount);
        }
    }

    function setWithdrawer(address _withdrawer) public {
        require(withdrawer == address(0));
        withdrawer = _withdrawer;
    }

    //////////////////////////// SWAP ////////////////////////////

    struct EstimateVars {
        address token0;
        address token1;
        address curPool;
    }

    function getAmountsOut(
        uint256 amountIn, address[] memory path, address[] memory pool
    ) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        require(path.length - 1 == pool.length);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        EstimateVars memory v;

        for (uint256 i = 0; i < path.length - 1; i++) {
            v.curPool = (pool[i] == address(0)) ? IV2Factory(v2Factory).tokenToPool(path[i], path[i + 1]) : pool[i];

            v.token0 = IExchange(v.curPool).token0();
            v.token1 = IExchange(v.curPool).token1();

            if (path[i] == v.token0) {
                require(path[i + 1] == v.token1, "Invalid path");
            } else if (path[i] == v.token1) {
                require(path[i + 1] == v.token0, "Invalid path");
            } else revert("Invalid path");

            if (pool[i] == address(0)) {
                amounts[i + 1] = IExchange(v.curPool).estimatePos(path[i], amounts[i]);
            } else {
                (amounts[i + 1], ) = IV3Estimator(estimator).estimatePos(pool[i], path[i], amounts[i]);
            }
        }
    }

    function getAmountsIn(
        uint256 amountOut, address[] memory path, address[] memory pool
    ) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        require(path.length - 1 == pool.length);

        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountOut;

        EstimateVars memory v;

        for (uint256 i = path.length - 1; i > 0; i--) {
            v.curPool = (pool[i - 1] == address(0)) ? IV2Factory(v2Factory).tokenToPool(path[i - 1], path[i]) : pool[i - 1];

            v.token0 = IExchange(v.curPool).token0();
            v.token1 = IExchange(v.curPool).token1();

            if (path[i - 1] == v.token0) {
                require(path[i] == v.token1, "Invalid path");
            } else if (path[i - 1] == v.token1) {
                require(path[i] == v.token0, "Invalid path");
            } else revert("Invalid path");

            if (pool[i - 1] == address(0)) {
                amounts[i - 1] = IExchange(v.curPool).estimateNeg(path[i], amounts[i]);
            } else {
                (amounts[i - 1], ) = IV3Estimator(estimator).estimateNeg(pool[i - 1], path[i], amounts[i]);
            }

        }
    }

    function _swapPos(address pool, address[] memory tokens, uint256 amount, uint256 amountOutMin) private {
        if (pool == address(0)) {
            TransferHelper.safeApprove(tokens[0], v2Router, type(uint256).max);
            IV2Router(v2Router).swapExactTokensForTokens(amount, amountOutMin, tokens, address(this), block.timestamp);
        } else {
            TransferHelper.safeApprove(tokens[0], v3Router, type(uint256).max);
            ISwapRouter(v3Router).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokens[0],
                    tokenOut: tokens[1],
                    fee: IUniswapV3Pool(pool).fee(),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amount,
                    amountOutMinimum: amountOutMin,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function _swapNeg(address pool, address[] memory tokens, uint256 amount, uint256 amountInMax) private {
        if (pool == address(0)) {
            TransferHelper.safeApprove(tokens[0], v2Router, type(uint256).max);
            IV2Router(v2Router).swapTokensForExactTokens(amount, amountInMax, tokens, address(this), block.timestamp);
        } else {
            TransferHelper.safeApprove(tokens[0], v3Router, type(uint256).max);
            ISwapRouter(v3Router).exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: tokens[0],
                    tokenOut: tokens[1],
                    fee: IUniswapV3Pool(pool).fee(),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amount,
                    amountInMaximum: amountInMax,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn, uint256 amountOutMin, SwapParams calldata p
    ) external ensure(p.deadline) returns (uint256[] memory amounts) {
        uint256 len = p.path.length;
        amounts = getAmountsOut(amountIn, p.path, p.pool);
        require(amounts[len - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(p.path[0], msg.sender, address(this), amounts[0]);
        for (uint256 i = 0; i < len - 1; i++) {
            _swapPos(p.pool[i], p.path[i:i + 2], amounts[i], amounts[i + 1]);
        }
        TransferHelper.safeTransfer(p.path[len - 1], p.to, amounts[len - 1]);
    }

    function swapTokensForExactTokens(
        uint256 amountOut, uint256 amountInMax, SwapParams calldata p
    ) external ensure(p.deadline) returns (uint256[] memory amounts) {
        uint256 len = p.path.length;
        amounts = getAmountsIn(amountOut, p.path, p.pool);
        require(amounts[0] <= amountInMax, "INSUFFICIENT_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(p.path[0], msg.sender, address(this), amounts[0]);
        for (uint256 i = 0; i < len - 1; i++) {
            _swapNeg(p.pool[i], p.path[i:i + 2], amounts[i + 1], amounts[i]);
        }
        TransferHelper.safeTransfer(p.path[len - 1], p.to, amounts[len - 1]);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin, SwapParams calldata p
    ) external payable ensure(p.deadline) returns (uint256[] memory amounts) {
        uint256 len = p.path.length;
        require(p.path[0] == WETH, "INVALID_PATH");
        amounts = getAmountsOut(msg.value, p.path, p.pool);
        require(amounts[len - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH9(WETH).deposit{value: msg.value}();
        for (uint256 i = 0; i < len - 1; i++) {
            _swapPos(p.pool[i], p.path[i:i + 2], amounts[i], amounts[i + 1]);
        }
        TransferHelper.safeTransfer(p.path[len - 1], p.to, amounts[len - 1]);
    }

    function swapTokensForExactETH(
        uint256 amountOut, uint256 amountInMax, SwapParams calldata p
    ) external ensure(p.deadline) returns (uint256[] memory amounts) {
        uint256 len = p.path.length;
        require(p.path[len - 1] == WETH, "INVALID_PATH");
        amounts = getAmountsIn(amountOut, p.path, p.pool);
        require(amounts[0] <= amountInMax, "INSUFFICIENT_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(p.path[0], msg.sender, address(this), amounts[0]);
        for (uint256 i = 0; i < len - 1; i++) {
            _swapNeg(p.pool[i], p.path[i:i + 2], amounts[i + 1], amounts[i]);
        }
        IWETH9(WETH).withdraw(amounts[len - 1]);
        TransferHelper.safeTransferETH(p.to, amounts[len - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn, uint256 amountOutMin, SwapParams calldata p
    ) external ensure(p.deadline) returns (uint256[] memory amounts) {
        uint256 len = p.path.length;
        require(p.path[len - 1] == WETH, "INVALID_PATH");
        amounts = getAmountsOut(amountIn, p.path, p.pool);
        require(amounts[len - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(p.path[0], msg.sender, address(this), amounts[0]);
        for (uint256 i = 0; i < len - 1; i++) {
            _swapPos(p.pool[i], p.path[i:i + 2], amounts[i], amounts[i + 1]);
        }
        IWETH9(WETH).withdraw(amounts[len - 1]);
        TransferHelper.safeTransferETH(p.to, amounts[len - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut, SwapParams calldata p
    ) external payable ensure(p.deadline) returns (uint256[] memory amounts) {
        uint256 len = p.path.length;
        uint256 amountETH = msg.value;
        require(p.path[0] == WETH, "INVALID_PATH");
        amounts = getAmountsIn(amountOut, p.path, p.pool);
        require(amounts[0] <= amountETH, "INSUFFICIENT_INPUT_AMOUNT");
        IWETH9(WETH).deposit{value: msg.value}();
        for (uint256 i = 0; i < len - 1; i++) {
            _swapNeg(p.pool[i], p.path[i:i + 2], amounts[i + 1], amounts[i]);
        }
        TransferHelper.safeTransfer(p.path[len - 1], p.to, amounts[len - 1]);
        if (amountETH > amounts[0]) {
            IWETH9(WETH).withdraw(amountETH - amounts[0]);
            TransferHelper.safeTransferETH(msg.sender, amountETH - amounts[0]);
        }
    }

    receive() external payable {
        require(msg.sender == WETH, 'Not Authorized');
    }
}
