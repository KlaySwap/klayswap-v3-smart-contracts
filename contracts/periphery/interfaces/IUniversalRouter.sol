// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface IUniversalRouter {
    struct SwapParams {
        address to;
        address[] path;
        address[] pool;
        uint256 deadline;
    }

    function Owner() external view returns (address);
    function WETH() external view returns (address);
    function _setImplementation(address _newImp) external;
    function _setImplementationAndCall(address _newImp, bytes calldata data) external;
    function changeOwner(address newOwner) external;
    function entered() external view returns (bool);
    function estimator() external view returns (address);
    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path,
        address[] calldata pool
    ) external view returns (uint256[] memory amounts);
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path,
        address[] calldata pool
    ) external view returns (uint256[] memory amounts);
    function implementation() external view returns (address);
    function swapETHForExactTokens(
        uint256 amountOut,
        SwapParams calldata p
    ) external returns (uint256[] memory amounts);
    function swapExactETHForTokens(
        uint256 amountOutMin,
        SwapParams calldata p
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        SwapParams calldata p
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        SwapParams calldata p
    ) external returns (uint256[] memory amounts);
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        SwapParams calldata p
    ) external returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        SwapParams calldata p
    ) external returns (uint256[] memory amounts);
    function v2Factory() external view returns (address);
    function v3Factory() external view returns (address);
    function v3Router() external view returns (address);
    function version() external pure returns (string memory);
}
