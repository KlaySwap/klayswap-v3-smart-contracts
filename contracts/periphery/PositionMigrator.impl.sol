// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "../core/interfaces/IUniswapV3Factory.sol";
import "../core/interfaces/IUniswapV3Pool.sol";
import "../core/interfaces/IERC20Minimal.sol";
import "../core/libraries/LowGasSafeMath.sol";
import "../core/libraries/TickMath.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/IV3Estimator.sol";
import './interfaces/external/IWETH9.sol';
import "./libraries/LiquidityAmounts.sol";
import "./libraries/PoolAddress.sol";
import "./libraries/TransferHelper.sol";
import './libraries/PositionValue.sol';
import "./base/PeripheryImmutableState.sol";

library LowGasSafeMath128 {
    /// @notice Returns x + y, reverts if sum overflows uint128
    /// @param x The augend
    /// @param y The addend
    /// @return z The sum of x and y
    function add(uint128 x, uint128 y) internal pure returns (uint128 z) {
        require((z = x + y) >= x);
    }

    /// @notice Returns x - y, reverts if underflows
    /// @param x The minuend
    /// @param y The subtrahend
    /// @return z The difference of x and y
    function sub(uint128 x, uint128 y) internal pure returns (uint128 z) {
        require((z = x - y) <= x);
    }

    /// @notice Returns x * y, reverts if overflows
    /// @param x The multiplicand
    /// @param y The multiplier
    /// @return z The product of x and y
    function mul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        require(x == 0 || (z = x * y) / x == y);
    }
}

/// @title V3 to V3 Position Migrator, Zapping
contract PositionMigratorImpl {

    using LowGasSafeMath for uint256;
    using LowGasSafeMath128 for uint128;

    struct MigrationParams {
        uint256 tokenId;
        // Burn
        uint256 burnAmount0Min;
        uint256 burnAmount1Min;
        // Swap
        address tokenIn;
        uint256 swapAmountIn;
        uint256 swapAmountOutMin;
        // Mint
        int24 tickLower;
        int24 tickUpper;
        uint256 mintAmount0Min;
        uint256 mintAmount1Min;
        uint256 deadline;
        bool compoundFee;
    }

    struct MigrationCache {
        address token0;
        address token1;
        uint24 fee;
        uint128 liquidity;
        uint256 balance0;
        uint256 balance1;
        uint256 fee0;
        uint256 fee1;
        bool zeroForOne;
        uint160 sqrtRatioX96;
    }

    struct Result {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        uint256 reward;
    }

    struct ZappingParams {
        IUniswapV3Pool pool;
        uint256 amount;
        int24 tickLower;
        int24 tickUpper;
        bool zeroForOne;
        uint256 mintAmount0Min;
        uint256 mintAmount1Min;
        uint256 tokenId;
        uint256 deadline;
    }

    uint256 public immutable NUMBER_MAX_STEP = 20;

    address public owner;
    address public nextOwner;
    address public factory;
    address public WETH9;
    address public rewardToken;
    INonfungiblePositionManager public nonfungiblePositionManager;
    ISwapRouter public router;
    IV3Estimator public estimator;
    address public treasury;

    bool public entered;

    modifier nonReentrant {
        require(!entered, "ReentrancyGuard: reentrant call");

        entered = true;

        _;

        entered = false;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function _initialize(
        address _owner,
        address _nonfungiblePositionManager,
        address _rewardToken,
        address _router,
        address _estimator,
        address _treasury
    ) external {
        require(owner == address(0));
        owner = _owner;
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);

        factory = nonfungiblePositionManager.factory();
        WETH9 = nonfungiblePositionManager.WETH9();
        rewardToken = _rewardToken;
        router = ISwapRouter(_router);
        estimator = IV3Estimator(_estimator);
        treasury = _treasury;
    }

    event ChangeNextOwner(address nextOwner);
    event ChangeOwner(address owner);
    event MigratePosition(address user, address token0, address token1, uint24 fee, uint256 burnId, uint256 mintId);
    event Zap(address user, address token0, address token1, uint24 fee, uint256 amount, bool zeroForOne, uint256 tokenId);

    function version() public pure returns (string memory) {
        return "PositionMigratorImpl20240528";
    }

    function changeNextOwner(address _nextOwner) external onlyOwner {
        nextOwner = _nextOwner;

        emit ChangeNextOwner(_nextOwner);
    }

    function changeOwner() external {
        require(msg.sender == nextOwner);

        owner = nextOwner;
        nextOwner = address(0);

        emit ChangeOwner(owner);
    }

    function changeEstimator(address _estimator) external onlyOwner {
        estimator = IV3Estimator(_estimator);
    }

    function inCaseTokensGetStuck(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            require(address(this).balance >= amount);
            TransferHelper.safeTransferETH(owner, amount);
        }
        else {
            require(IERC20Minimal(token).balanceOf(address(this)) >= amount);
            TransferHelper.safeTransfer(token, owner, amount);
        }
    }

    function sendTokenToUser(address token, uint256 amount) private {
        if (token == WETH9) {
            IWETH9(WETH9).withdraw(amount);
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            TransferHelper.safeTransfer(token, msg.sender, amount);
        }
    }

    function migrate(MigrationParams calldata params)
        external
        nonReentrant
    {
        MigrationCache memory c;
        Result memory r;

        require(msg.sender == nonfungiblePositionManager.ownerOf(params.tokenId));

        (,, c.token0, c.token1, c.fee, ,, c.liquidity,,,,)
            = nonfungiblePositionManager.positions(params.tokenId);

        IERC20Minimal token0 = IERC20Minimal(c.token0);
        IERC20Minimal token1 = IERC20Minimal(c.token1);

        // 1. Burn
        {
            require(c.liquidity != 0, "Liquidity is 0");

            (uint256 burn0, uint256 burn1) = nonfungiblePositionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: params.tokenId,
                    liquidity : c.liquidity,
                    amount0Min: params.burnAmount0Min,
                    amount1Min: params.burnAmount1Min,
                    deadline: params.deadline
                })
            );

            require(burn0 >= params.burnAmount0Min, "Burn Slippage");
            require(burn1 >= params.burnAmount1Min, "Burn Slippage");

            (c.balance0, c.balance1, r.reward) = nonfungiblePositionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: params.tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

            nonfungiblePositionManager.burn(params.tokenId);

            if (!params.compoundFee) {
                c.fee0 = c.balance0.sub(burn0);
                c.fee1 = c.balance1.sub(burn1);
                c.balance0 = burn0;
                c.balance1 = burn1;
            }
        }

        // 2. Swap
        if (params.swapAmountIn > 0) {
            c.zeroForOne = (params.tokenIn == c.token0);
            uint256 balance0Before = token0.balanceOf(address(this));
            uint256 balance1Before = token1.balanceOf(address(this));

            (c.zeroForOne) ?
                TransferHelper.safeApprove(c.token0, address(router), balance0Before) :
                TransferHelper.safeApprove(c.token1, address(router), balance1Before);

            ISwapRouter(router).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: (c.zeroForOne) ? c.token0 : c.token1,
                    tokenOut: (c.zeroForOne) ? c.token1 : c.token0,
                    fee: c.fee,
                    recipient: address(this),
                    deadline: params.deadline,
                    amountIn: params.swapAmountIn,
                    amountOutMinimum: params.swapAmountOutMin,
                    sqrtPriceLimitX96: 0
                })

            );

            uint256 balance0After = token0.balanceOf(address(this));
            uint256 balance1After = token1.balanceOf(address(this));

            if (c.zeroForOne) {
                require(balance1After >= balance1Before.add(params.swapAmountOutMin), "Swap Slippage");
                c.balance0 = c.balance0.sub(balance0Before.sub(balance0After));
                c.balance1 = c.balance1.add(balance1After.sub(balance1Before));
            } else {
                require(balance0After >= balance0Before.add(params.swapAmountOutMin), "Swap Slippage");
                c.balance0 = c.balance0.add(balance0After.sub(balance0Before));
                c.balance1 = c.balance1.sub(balance1Before.sub(balance1After));
            }
        }

        // 3. mint
        TransferHelper.safeApprove(c.token0, address(nonfungiblePositionManager), c.balance0);
        TransferHelper.safeApprove(c.token1, address(nonfungiblePositionManager), c.balance1);

        (r.tokenId, r.liquidity, r.amount0, r.amount1) = nonfungiblePositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: c.token0,
                token1: c.token1,
                fee: c.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: c.balance0,
                amount1Desired: c.balance1,
                amount0Min: params.mintAmount0Min,
                amount1Min: params.mintAmount1Min,
                recipient: msg.sender,
                deadline: params.deadline
            })
        );

        sendTokenToUser(c.token0, c.balance0.add(c.fee0).sub(r.amount0));
        sendTokenToUser(c.token1, c.balance1.add(c.fee1).sub(r.amount1));
        TransferHelper.safeTransfer(rewardToken, msg.sender, r.reward);

        emit MigratePosition(msg.sender, c.token0, c.token1, c.fee, params.tokenId, r.tokenId);
    }

    function zapWithETH(ZappingParams memory params) external payable nonReentrant {
        ZappingParams memory p = params;

        if (params.tokenId != 0) {
            (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(params.tokenId);
            p.tickLower = tickLower;
            p.tickUpper = tickUpper;
            p.pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})));
        }

        if (p.pool.token0() == WETH9) {
            p.zeroForOne = true;
        } else if (p.pool.token1() == WETH9) {
            p.zeroForOne = false;
        } else {
            revert();
        }

        p.amount = msg.value;
        IWETH9(WETH9).deposit{value: msg.value}();

        (uint256 refund0, uint256 refund1) = zap(p, true);

        sendTokenToUser(p.pool.token0(), refund0);
        sendTokenToUser(p.pool.token1(), refund1);
    }

    function zapWithToken(ZappingParams memory params) external nonReentrant {
        ZappingParams memory p = params;

        if (params.tokenId != 0) {
            (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(params.tokenId);
            p.tickLower = tickLower;
            p.tickUpper = tickUpper;
            p.pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})));
        }

        (uint256 refund0, uint256 refund1) = zap(p, false);

        sendTokenToUser(p.pool.token0(), refund0);
        sendTokenToUser(p.pool.token1(), refund1);
    }

    /// @notice zap
    function zap(ZappingParams memory params, bool isETH) private returns (uint256, uint256) {
        MigrationCache memory c;
        Result memory r;
        address token0;
        address token1;

        token0 = params.pool.token0();
        token1 = params.pool.token1();
        c.fee = params.pool.fee();

        (uint256 amountIn, uint256 amountOut) = getZapSwapAmt(params);

        c.balance0 = IERC20Minimal(token0).balanceOf(address(this));
        c.balance1 = IERC20Minimal(token1).balanceOf(address(this));

        if (isETH) {
            (params.zeroForOne) ? c.balance0 -= params.amount : c.balance1 -= params.amount;
        } else {
            (params.zeroForOne) ?
                TransferHelper.safeTransferFrom(token0, msg.sender, address(this), params.amount) :
                TransferHelper.safeTransferFrom(token1, msg.sender, address(this), params.amount);
        }

        // 1. Swap
        if (amountIn > 0) {
            (params.zeroForOne) ?
                TransferHelper.safeApprove(token0, address(router), params.amount) :
                TransferHelper.safeApprove(token1, address(router), params.amount);

                ISwapRouter(router).exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: (params.zeroForOne) ? token0 : token1,
                        tokenOut: (params.zeroForOne) ? token1 : token0,
                        fee: c.fee,
                        recipient: address(this),
                        deadline: params.deadline,
                        amountIn: amountIn,
                        amountOutMinimum: amountOut,
                        sqrtPriceLimitX96: 0
                    })
            );
        }

        c.balance0 = IERC20Minimal(token0).balanceOf(address(this)).sub(c.balance0);
        c.balance1 = IERC20Minimal(token1).balanceOf(address(this)).sub(c.balance1);

        // 2. mint
        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), c.balance0);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), c.balance1);

        if (params.tokenId == 0) {
            (r.tokenId, r.liquidity, r.amount0, r.amount1) = nonfungiblePositionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: c.fee,
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    amount0Desired: c.balance0,
                    amount1Desired: c.balance1,
                    amount0Min: params.mintAmount0Min,
                    amount1Min: params.mintAmount1Min,
                    recipient: msg.sender,
                    deadline: params.deadline
                })
            );
        } else {
            (r.liquidity, r.amount0, r.amount1) = nonfungiblePositionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: params.tokenId,
                    amount0Desired: c.balance0,
                    amount1Desired: c.balance1,
                    amount0Min: params.mintAmount0Min,
                    amount1Min: params.mintAmount1Min,
                    deadline: params.deadline
                })
            );
            r.tokenId = params.tokenId;
        }

        require(r.amount0 >= params.mintAmount0Min, "mintAmount0");
        require(r.amount1 >= params.mintAmount1Min, "mintAmount1");

        emit Zap(msg.sender, token0, token1, c.fee, params.amount, params.zeroForOne, r.tokenId);

        return (c.balance0.sub(r.amount0), c.balance1.sub(r.amount1));
    }

    /////////////////////////////////////////////////////////////////////////////////

    struct EstInfo {
        uint128 maxLP;
        uint256 maxInput;
        uint256 maxOutput;
        uint160 minPriceX96;
        uint160 maxPriceX96;
        uint256 swap;
        uint256 diff;
        uint256 step;
    }

    struct StepVars {
        uint160 newPriceX96;
        uint256 output;
        uint128 estLP;
        bool pos;
    }

    function getPoolAddress(address tokenA, address tokenB, uint24 fee) internal view returns (address pool) {
        pool = PoolAddress.computeAddress(address(factory), PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    /// @return maxInput
    /// @return maxOutput
    function getZapSwapAmt(ZappingParams memory p) public view returns (uint256, uint256) {
        require(IUniswapV3Factory(factory).poolExist(address(p.pool)));
        if (p.amount == 0) return (0, 0);

        address token0 = p.pool.token0();
        address token1 = p.pool.token1();
        (uint160 curPrice,,,,,,) = p.pool.slot0();

        if (p.tokenId != 0) {
            (,, address t0, address t1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(p.tokenId);
            token0 = t0;
            token1 = t1;
            p.tickLower = tickLower;
            p.tickUpper = tickUpper;
            p.pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})));
        }

        EstInfo memory e = EstInfo({
            maxLP: 0,
            maxInput: 0,
            maxOutput: 0,
            minPriceX96 : TickMath.getSqrtRatioAtTick(p.tickLower),
            maxPriceX96 : TickMath.getSqrtRatioAtTick(p.tickUpper),
            swap: p.amount / 2,
            diff: p.amount / 2,
            step: 0
        });

        if (p.zeroForOne) {
            if (curPrice <= e.minPriceX96) return (0, 0);

            while (e.step < NUMBER_MAX_STEP) {
                StepVars memory v;

                (v.output, v.newPriceX96) = estimator.estimatePos(address(p.pool), token0, e.swap);

                (v.estLP, v.pos) = LiquidityAmounts.getLiquidityForAmountsWithHelper(
                    v.newPriceX96, e.minPriceX96, e.maxPriceX96, p.amount.sub(e.swap), v.output
                );

                if (e.maxLP <= v.estLP) {
                    e.maxLP = v.estLP;
                    e.maxInput = e.swap;
                    e.maxOutput = v.output;
                }

                e.step += 1;
                e.diff = e.diff / 2;
                e.swap = (v.pos) ? e.swap.sub(e.diff) : e.swap.add(e.diff);
            }
        } else {
            if (curPrice >= e.maxPriceX96) return (0, 0);

            while (e.step < NUMBER_MAX_STEP) {
                StepVars memory v;

                (v.output, v.newPriceX96) = estimator.estimatePos(address(p.pool), token1, e.swap);

                (v.estLP, v.pos) = LiquidityAmounts.getLiquidityForAmountsWithHelper(
                    v.newPriceX96, e.minPriceX96, e.maxPriceX96, v.output, p.amount.sub(e.swap)
                );

                if (e.maxLP <= v.estLP) {
                    e.maxLP = v.estLP;
                    e.maxInput = e.swap;
                    e.maxOutput = v.output;
                }

                e.step += 1;
                e.diff = e.diff / 2;
                e.swap = (v.pos) ? e.swap.add(e.diff) : e.swap.sub(e.diff);
            }
        }

        return (e.maxInput, e.maxOutput);
    }

    /// @return maxInput
    /// @return maxOutput
    /// @return zeroForOne
    function getMigrationSwapAmt(
        uint256 tokenId, int24 tickLower, int24 tickUpper, bool compoundFee
    ) public view returns (uint256, uint256, bool) {
        MigrationCache memory c;

        (,, c.token0, c.token1, c.fee,,,,,,,) = nonfungiblePositionManager.positions(tokenId);
        IUniswapV3Pool pool = IUniswapV3Pool(getPoolAddress(c.token0, c.token1, c.fee));
        (c.sqrtRatioX96,,,,,,) = pool.slot0();

        (c.balance0, c.balance1) =
            (compoundFee) ?
                PositionValue.total(nonfungiblePositionManager, treasury, tokenId, c.sqrtRatioX96) :
                PositionValue.principal(nonfungiblePositionManager, tokenId, c.sqrtRatioX96);

        EstInfo memory e = EstInfo({
            maxLP: 0,
            maxInput: 0,
            maxOutput: 0,
            minPriceX96 : TickMath.getSqrtRatioAtTick(tickLower),
            maxPriceX96 : TickMath.getSqrtRatioAtTick(tickUpper),
            swap: 0,
            diff: 0,
            step: 0
        });

        (, c.zeroForOne) = LiquidityAmounts.getLiquidityForAmountsWithHelper(
                c.sqrtRatioX96,
                e.minPriceX96,
                e.maxPriceX96,
                c.balance0,
                c.balance1
            );

        c.zeroForOne = !c.zeroForOne;
        e.swap = e.diff = c.zeroForOne ? c.balance0 / 2 : c.balance1 / 2;

        if (c.zeroForOne) {
            if (c.sqrtRatioX96 <= e.minPriceX96) return (0, 0, c.zeroForOne);
            if (c.sqrtRatioX96 >= e.maxPriceX96) {
                (uint256 maxOutput, ) = estimator.estimatePosForMigration(address(pool), c.token0, c.balance0, tokenId);
                return (c.balance0, maxOutput, c.zeroForOne);
            }

            while (e.step < NUMBER_MAX_STEP) {
                StepVars memory v;

                (v.output, v.newPriceX96) = estimator.estimatePosForMigration(address(pool), c.token0, e.swap, tokenId);

                (v.estLP, v.pos) = LiquidityAmounts.getLiquidityForAmountsWithHelper(
                    v.newPriceX96, e.minPriceX96, e.maxPriceX96, c.balance0.sub(e.swap), c.balance1.add(v.output)
                );

                if (e.maxLP <= v.estLP) {
                    e.maxLP = v.estLP;
                    e.maxInput = e.swap;
                    e.maxOutput = v.output;
                }

                e.step += 1;
                e.diff = e.diff / 2;
                e.swap = (v.pos) ? e.swap.sub(e.diff) : e.swap.add(e.diff);
            }
        } else {
            if (c.sqrtRatioX96 >= e.maxPriceX96) return (0, 0, c.zeroForOne);
            if (c.sqrtRatioX96 <= e.minPriceX96) {
                (uint256 maxOutput, ) = estimator.estimatePosForMigration(address(pool), c.token1, c.balance1, tokenId);
                return (c.balance1, maxOutput, c.zeroForOne);
            }

            while (e.step < NUMBER_MAX_STEP) {
                StepVars memory v;

                (v.output, v.newPriceX96) = estimator.estimatePosForMigration(address(pool), c.token1, e.swap, tokenId);

                (v.estLP, v.pos) = LiquidityAmounts.getLiquidityForAmountsWithHelper(
                    v.newPriceX96, e.minPriceX96, e.maxPriceX96, c.balance0.add(v.output), c.balance1.sub(e.swap)
                );

                if (e.maxLP <= v.estLP) {
                    e.maxLP = v.estLP;
                    e.maxInput = e.swap;
                    e.maxOutput = v.output;
                }

                e.step += 1;
                e.diff = e.diff / 2;
                e.swap = (v.pos) ? e.swap.add(e.diff) : e.swap.sub(e.diff);
            }
        }

        return (e.maxInput, e.maxOutput, c.zeroForOne);
    }

    receive() external payable {
        require(msg.sender == WETH9);
    }
}