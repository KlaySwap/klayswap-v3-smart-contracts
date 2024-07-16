// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';
import './UniswapV3PoolDeployer.sol';
import './UniswapV3Pool.sol';
import '../interfaces/IGovernance.sol';
import '../interfaces/IV2Factory.sol';
import '../interfaces/IRewardToken.sol';

/// @title Canonical Uniswap V3 factory
/// @notice Deploys Uniswap V3 pools and manages ownership and control over pool protocol fees
contract UniswapV3FactoryImpl is IUniswapV3Factory, UniswapV3PoolDeployer {

    address public override owner;
    address public override policyAdmin;
    address public override governance;
    address public override v2Factory;
    address public override WETH;
    address public override treasury;
    address public override rewardToken;

    mapping(uint24 => int24) public override feeAmountTickSpacing;
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;
    mapping(address => bool) public override poolExist;
    address[] public override pools;

    function version() public pure returns (string memory) {
        return "V3FactoryImpl20240528";
    }

    function _initialize(
        address _governance,
        address _WETH
    ) external {
        require(owner == address(0));
        owner = msg.sender;
        WETH = _WETH;
        governance = _governance;
        if (governance != address(0)) {
            v2Factory = IGovernance(_governance).factory();
            rewardToken = IGovernance(_governance).rewardToken();
        }

        feeAmountTickSpacing[500] = 1;
        emit FeeAmountEnabled(500, 1);
        feeAmountTickSpacing[2000] = 40;
        emit FeeAmountEnabled(2000, 40);
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override returns (address pool) {
        pool = _createPool(tokenA, tokenB, fee);
    }

    function _createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));

        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        poolExist[pool] = true;
        pools.push(pool);

        emit PoolCreated(token0, token1, fee, tickSpacing, pool, pools.length - 1);
    }

    /// @inheritdoc IUniswapV3Factory
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    function setPolicyAdmin(address _policyAdmin) external override {
        require(msg.sender == owner);
        emit SetPolicyAdmin(_policyAdmin);
        policyAdmin = _policyAdmin;
    }

    function setTreasury(address _treasury) external {
        require(msg.sender == owner);
        treasury = _treasury;
    }

    /// @inheritdoc IUniswapV3Factory
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }

    function getPoolCount() external view override returns (uint256) {
        return pools.length;
    }

    function getPoolAddress(uint256 idx) external view override returns (address) {
        require(idx < pools.length);
        return pools[idx];
    }

    function getInitCodeHash() external pure returns (bytes32) {
        bytes memory bytecode = type(UniswapV3Pool).creationCode;

        // Compute the hash of the bytecode
        return (keccak256(bytecode));
    }
}
