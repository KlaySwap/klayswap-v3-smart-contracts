// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IExchange {
    function name() external view returns (string memory);
    function initPool() external;
    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
    function approve(address _spender, uint256 _value) external returns (bool);
    function token0() external view returns (address);
    function totalSupply() external view returns (uint256);
    function getCurrentPool() external view returns (uint256, uint256);
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool);
    function addTokenLiquidityWithLimit(
        uint256 amount0,
        uint256 amount1,
        uint256 minAmount0,
        uint256 minAmount1,
        address user
    ) external returns (uint256 real0, uint256 real1, uint256 amountLP);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function decimals() external view returns (uint8);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function getTreasury() external view returns (address);
    function reserve0() external view returns (uint112);
    function version() external pure returns (string memory);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function reserve1() external view returns (uint112);
    function userRewardSum(address) external view returns (uint256);
    function exchangeNeg(
        address token,
        uint256 amount
    ) external returns (uint256);
    function mining() external view returns (uint256);
    function changeFee(uint256 _fee) external;
    function balanceOf(address) external view returns (uint256);
    function kLast() external view returns (uint256);
    function nonces(address) external view returns (uint256);
    function miningIndex() external view returns (uint256);
    function symbol() external view returns (string memory);
    function entered() external view returns (bool);
    function transfer(address _to, uint256 _value) external returns (bool);
    function WETH() external view returns (address);
    function lastMined() external view returns (uint256);
    function claimReward() external;
    function skim(address to) external;
    function estimateNeg(
        address token,
        uint256 amount
    ) external view returns (uint256);
    function updateMiningIndex() external returns (uint256);
    function factory() external view returns (address);
    function blockTimestampLast() external view returns (uint32);
    function exchangePos(
        address token,
        uint256 amount
    ) external returns (uint256);
    function token1() external view returns (address);
    function claimReward(address user) external;
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function allowance(address, address) external view returns (uint256);
    function removeLiquidityWithLimit(
        uint256 amount,
        uint256 minAmount0,
        uint256 minAmount1,
        address user
    ) external returns (uint256, uint256);
    function fee() external view returns (uint256);
    function estimatePos(
        address token,
        uint256 amount
    ) external view returns (uint256);
    function userLastIndex(address) external view returns (uint256);
    function rewardToken() external view returns (address);
    function router() external view returns (address);
    function sync() external;
}
