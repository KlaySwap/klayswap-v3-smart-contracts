// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../core/interfaces/IUniswapV3Factory.sol';
import '../core/interfaces/IUniswapV3Pool.sol';
import '../core/libraries/LowGasSafeMath.sol';
import './V3AirdropOperator.sol';

library DistributionId {
    /// @notice Calculate the key for a staking incentive
    function compute(address operator, address token, address pool) internal pure returns (bytes32 incentiveId) {
        return keccak256(abi.encode(operator, token, pool));
    }
}

/// @title V3Treasury
/// @dev Airdrop tokens should be token0 or token1
contract V3TreasuryImpl {
    using LowGasSafeMath for uint256;

    struct Distribution {
        address operator;
        address token;
        uint256 totalAmount;
        uint256 blockAmount;
        uint256 distributableBlock;
        uint256 distributedAmount;
        uint256 calcAmount;
    }

    address public owner;
    address public nextOwner;
    address public policyAdmin;

    IUniswapV3Factory public factory;

    mapping (address => bool) public validOperator;
    mapping (bytes32 => Distribution) public distributions;
    mapping (address => mapping(uint256 => bytes32)) public distributionEntries;
    mapping (address => uint256) public distributionCount;
    mapping (address => bool) public deployedOperator;

    bool public entered = false;

    event ChangeNextOwner(address nextOwner);
    event ChangeOwner(address owner);
    event SetOperator(address operator, bool valid);
    event DeployAirdropOperator(address operator);

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    modifier onlyOperator {
        require(validOperator[msg.sender]);
        _;
    }

    modifier nonReentrant {
        require(!entered, "ReentrancyGuard: reentrant call");

        entered = true;

        _;

        entered = false;
    }

    modifier onlyPolicyAdmin {
        require(msg.sender == owner || msg.sender == policyAdmin);
        _;
    }

    function _initialize(address _owner, address _factory) external {
        require(address(factory) == address(0));

        owner = _owner;
        factory = IUniswapV3Factory(_factory);
    }

    function version() external pure returns (string memory) {
        return "V3TreasuryImpl20240528";
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

    function setPolicyAdmin(address _policyAdmin) external onlyOwner {
        policyAdmin = _policyAdmin;
    }

    function setOperator(address _operator, bool _valid) external onlyPolicyAdmin {
        require(deployedOperator[_operator]);

        validOperator[_operator] = _valid;

        emit SetOperator(_operator, _valid);
    }

    function setValidOperatorList(address[] memory operators) external onlyPolicyAdmin {
        for(uint256 i = 0; i < operators.length; i++){
            require(deployedOperator[operators[i]]);

            validOperator[operators[i]] = true;

            emit SetOperator(operators[i], true);
        }
    }

    function getDistributionInfo(bytes32 id) external view returns (
        uint256 totalAmount,
        uint256 blockAmount,
        uint256 distributableBlock,
        uint256 endBlock,
        uint256 distributed
    ) {
        uint256 calcAmount;
        Distribution memory d = distributions[id];
        (totalAmount, blockAmount, distributableBlock, calcAmount)
            = (d.totalAmount, d.blockAmount, d.distributableBlock, d.calcAmount);
        endBlock = distributableBlock + (totalAmount - calcAmount) / blockAmount;
        distributed = distribution(d);
    }

    function deployAirdropOperator(address token, address pool) external returns (address operator) {
        require(factory.poolExist(pool), "NP");
        require(token == IUniswapV3Pool(pool).token0() || token == IUniswapV3Pool(pool).token1(), "NT");

        operator = address(new V3AirdropOperator(msg.sender, token, pool));
        deployedOperator[operator] = true;

        emit DeployAirdropOperator(operator);
    }

    /////////// for AirdropOperator

    event CreateDistribution(address operator, address token, address pool, uint256 amount, uint256 blockAmount, uint256 blockNumber);
    event Deposit(address operator, address token, address pool, uint256 amount);
    event RefixBlockAmount(address operator, address token, address pool, uint256 blockAmount);

    function create(
        address token,
        address pool,
        uint256 amount,
        uint256 blockAmount,
        uint256 blockNumber
    ) external onlyOperator nonReentrant {
        require(factory.poolExist(pool), "NP");
        require(token == IUniswapV3Pool(pool).token0() || token == IUniswapV3Pool(pool).token1(), "NT");
        require(blockNumber >= block.number);
        require(amount != 0 && blockAmount != 0);

        bytes32 id = DistributionId.compute(msg.sender, token, pool);
        require(distributions[id].operator == address(0));

        distributions[id] = Distribution({
            operator: msg.sender,
            token: token,
            totalAmount: amount,
            blockAmount: blockAmount,
            distributableBlock: blockNumber,
            distributedAmount: 0,
            calcAmount: 0
        });

        require(IERC20Minimal(token).transferFrom(msg.sender, pool, amount));

        uint256 index = distributionCount[pool];

        distributionEntries[pool][index] = id;
        distributionCount[pool] = index + 1;

        emit CreateDistribution(msg.sender, token, pool, amount, blockAmount, blockNumber);
    }

    function deposit(address token, address pool, uint256 amount) external onlyOperator nonReentrant {
        bytes32 id = DistributionId.compute(msg.sender, token, pool);
        require(amount != 0);
        Distribution storage d = distributions[id];
        require(d.operator != address(0), "NI");

        require(IERC20Minimal(token).transferFrom(msg.sender, pool, amount));

        d.calcAmount = distribution(d);
        d.distributableBlock = block.number;
        d.totalAmount = d.totalAmount.add(amount);

        emit Deposit(msg.sender, token, pool, amount);
    }

    function refixBlockAmount(address token, address pool, uint256 blockAmount) external onlyOperator nonReentrant {
        bytes32 id = DistributionId.compute(msg.sender, token, pool);
        require(blockAmount != 0);

        Distribution storage d = distributions[id];
        require(d.operator != address(0), "NI");

        d.calcAmount = distribution(d);
        d.distributableBlock = block.number;
        d.blockAmount = blockAmount;

        emit RefixBlockAmount(msg.sender, token, pool, blockAmount);
    }

    function getAirdropAmount() external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(factory.poolExist(msg.sender));

        if (distributionCount[msg.sender] == 0) return (0, 0);
        address token0 = IUniswapV3Pool(msg.sender).token0();
        for (uint256 i = 0; i < distributionCount[msg.sender]; i++) {
            Distribution storage d = distributions[distributionEntries[msg.sender][i]];
            uint256 thisMined = distribution(d);
            if (thisMined == 0) continue;

            (d.token == token0) ?
                amount0 = amount0.add(distribution(d).sub(d.distributedAmount)) :
                amount1 = amount1.add(distribution(d).sub(d.distributedAmount));
            d.distributedAmount = thisMined;
            d.calcAmount = thisMined;
            d.distributableBlock = block.number;
        }
    }

    function distribution(Distribution memory d) public view returns (uint256) {
        if (d.distributableBlock == 0 || d.distributableBlock > block.number) return d.calcAmount;

        uint256 amount = d.calcAmount.add(block.number.sub(d.distributableBlock).mul(d.blockAmount));

        return amount > d.totalAmount ? d.totalAmount : amount;
    }

    function getPoolAirdropAmount(address pool) external view returns (uint256 amount0, uint256 amount1) {
        if (distributionCount[pool] == 0) return (0, 0);

        address token0 = IUniswapV3Pool(pool).token0();
        for (uint256 i = 0; i < distributionCount[pool]; i++) {
            Distribution storage d = distributions[distributionEntries[pool][i]];
            uint256 thisMined = distribution(d);
            if (thisMined == 0) continue;

            (d.token == token0) ?
                amount0 = amount0.add(distribution(d).sub(d.distributedAmount)) :
                amount1 = amount1.add(distribution(d).sub(d.distributedAmount));
        }
    }
}