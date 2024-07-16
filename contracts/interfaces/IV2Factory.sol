// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IV2Factory {
    function getPoolAddress(uint256 idx) external view returns (address);
    function allPairs(uint256 idx) external view returns (address pair);
    function createETHPool(
        address token,
        uint256 amount,
        uint256 fee
    ) external payable;
    function version() external pure returns (string memory);
    function allPairsLength() external view returns (uint256);
    function getExchangeImplementation() external view returns (address);
    function implementation() external view returns (address);
    function changeNextOwner(address _nextOwner) external;
    function changeOwner() external;
    function nextOwner() external view returns (address);
    function _setExchangeImplementation(address _newExImp) external;
    function poolExist(address) external view returns (bool);
    function owner() external view returns (address);
    function getPoolCount() external view returns (uint256);
    function entered() external view returns (bool);
    function pools(uint256) external view returns (address);
    function WETH() external view returns (address);
    function createTokenPool(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        uint256 fee
    ) external;
    function createFee() external view returns (uint256);
    function _setImplementation(address _newImp) external;
    function setRouter(address _router) external;
    function exchangeImplementation() external view returns (address);
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
    function changeCreateFee(uint256 _createFee) external;
    function changePoolFee(
        address token0,
        address token1,
        uint256 fee
    ) external;
    function rewardToken() external view returns (address);
    function router() external view returns (address);
    function tokenToPool(address, address) external view returns (address);
}
