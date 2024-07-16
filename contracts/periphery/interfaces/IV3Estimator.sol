// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

interface IV3Estimator {
    function estimate(
        address pool,
        bool zeroForOne,
        int256 amountSpecified
    )
        external
        view
        returns (int256 amount0, int256 amount1, uint160 sqrtPriceX96After);
    function estimateForMigration(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 burnTokenId
    )
        external
        view
        returns (int256 amount0, int256 amount1, uint160 sqrtPriceX96After);
    function estimateNeg(
        address pool,
        address token,
        uint256 amountOut
    ) external view returns (uint256 amountIn, uint160 sqrtPriceX96After);
    function estimatePos(
        address pool,
        address token,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint160 sqrtPriceX96After);
    function estimatePosForMigration(
        address pool,
        address token,
        uint256 amountIn,
        uint256 burnTokenId
    ) external view returns (uint256 amountOut, uint160 sqrtPriceX96After);
    function nonfungiblePositionManager() external view returns (address);
}
