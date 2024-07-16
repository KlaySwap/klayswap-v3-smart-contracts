// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "../core/interfaces/IUniswapV3Pool.sol";
import '../core/libraries/LowGasSafeMath.sol';
import '../core/libraries/SafeCast.sol';
import '../core/libraries/TickBitmap.sol';
import '../core/libraries/TickMath.sol';
import '../core/libraries/SwapMath.sol';
import '../core/libraries/LiquidityMath.sol';
import "./interfaces/INonfungiblePositionManager.sol";

/// @title Swap Estimating by view function
contract V3Estimator {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;

    INonfungiblePositionManager public nonfungiblePositionManager;

    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        uint160 sqrtPriceLimitX96;
        // the tick associated with the current price
        int24 tick;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    struct BurnedPosition {
        uint160 sqrtPriceX96;
        int24 tick;
        int24 lower;
        int24 upper;
        uint128 liquidityBurned;
        bool exactInput;
    }

    constructor(address _nonfungiblePositionManager) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
    }

    function version() public pure returns (string memory) {
        return "V3Estimator20240528";
    }

    function estimatePos(IUniswapV3Pool pool, address token, uint256 amountIn) external view returns (uint256 amountOut, uint160 sqrtPriceX96After) {
         bool zeroForOne;
        if (token == pool.token0()) {
            zeroForOne = true;
        } else if (token == pool.token1()) {
            zeroForOne = false;
        } else {
            revert();
        }

        (int256 amount0, int256 amount1, uint160 _sqrtPriceX96After) = estimate(pool, zeroForOne, amountIn.toInt256());
        amountOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);
        sqrtPriceX96After = _sqrtPriceX96After;
    }

    function estimateNeg(IUniswapV3Pool pool, address token, uint256 amountOut) external view returns (uint256 amountIn, uint160 sqrtPriceX96After) {
        bool zeroForOne;
        if (token == pool.token0()) {
            zeroForOne = false;
        } else if (token == pool.token1()) {
            zeroForOne = true;
        } else {
            revert();
        }

        (int256 amount0, int256 amount1, uint160 _sqrtPriceX96After) = estimate(pool, zeroForOne, -amountOut.toInt256());
        amountIn = zeroForOne ? uint256(amount0) : uint256(amount1);
        sqrtPriceX96After = _sqrtPriceX96After;
    }

    function estimate(
        IUniswapV3Pool pool,
        bool zeroForOne,
        int256 amountSpecified
    ) public view returns (int256 amount0, int256 amount1, uint160 sqrtPriceX96After) {
        require(amountSpecified != 0, 'AS');

        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();

        bool exactInput = amountSpecified > 0;

        SwapState memory state =
            SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: sqrtPriceX96,
                sqrtPriceLimitX96 : zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                tick: tick,
                liquidity: pool.liquidity()
            });

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != state.sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = nextInitializedTickWithinOneWord(
                pool,
                state.tick,
                pool.tickSpacing(),
                zeroForOne
            );

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < state.sqrtPriceLimitX96 : step.sqrtPriceNextX96 > state.sqrtPriceLimitX96)
                    ? state.sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                pool.fee()
            );

            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

           // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    (, int128 liquidityNet,,,,,,,) = pool.ticks(step.tickNext);
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }

                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);
        sqrtPriceX96After = state.sqrtPriceX96;
    }

    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(tick % 256);
    }

    function nextInitializedTickWithinOneWord(
        IUniswapV3Pool pool,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // all the 1s at or to the right of the current bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = pool.tickBitmap(wordPos) & mask;

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // all the 1s at or to the left of the bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = pool.tickBitmap(wordPos) & mask;

            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }

    //////////////////////////// For Migration ////////////////////////////

    function estimatePosForMigration(IUniswapV3Pool pool, address token, uint256 amountIn, uint256 burnTokenId) external view returns (uint256 amountOut, uint160 sqrtPriceX96After) {
         bool zeroForOne;
        if (token == pool.token0()) {
            zeroForOne = true;
        } else if (token == pool.token1()) {
            zeroForOne = false;
        } else {
            revert();
        }

        (int256 amount0, int256 amount1, uint160 _sqrtPriceX96After) = estimateForMigration(pool, zeroForOne, amountIn.toInt256(), burnTokenId);
        amountOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);
        sqrtPriceX96After = _sqrtPriceX96After;
    }

    function estimateForMigration(
        IUniswapV3Pool pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 burnTokenId
    ) public view returns (int256 amount0, int256 amount1, uint160 sqrtPriceX96After) {
        require(amountSpecified != 0, 'AS');

        BurnedPosition memory b;

        (b.sqrtPriceX96, b.tick,,,,,) = pool.slot0();
        b.exactInput = amountSpecified > 0;
        (,,,,, b.lower, b.upper, b.liquidityBurned,,,,)
            = nonfungiblePositionManager.positions(burnTokenId);

        SwapState memory state =
            SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: b.sqrtPriceX96,
                sqrtPriceLimitX96 : zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                tick: b.tick,
                liquidity: (b.lower <= b.tick && b.tick <= b.upper) ? pool.liquidity() - b.liquidityBurned : pool.liquidity()
            });

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != state.sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = nextInitializedTickWithinOneWord(
                pool,
                state.tick,
                pool.tickSpacing(),
                zeroForOne
            );

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < state.sqrtPriceLimitX96 : step.sqrtPriceNextX96 > state.sqrtPriceLimitX96)
                    ? state.sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                pool.fee()
            );

            if (b.exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

           // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    (, int128 liquidityNet,,,,,,,) = pool.ticks(step.tickNext);
                    if (step.tickNext == b.lower) {
                        liquidityNet -= int128(b.liquidityBurned);
                    } else if (step.tickNext == b.upper) {
                        liquidityNet += int128(b.liquidityBurned);
                    }
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }

                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        (amount0, amount1) = zeroForOne == b.exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);
        sqrtPriceX96After = state.sqrtPriceX96;
    }
}