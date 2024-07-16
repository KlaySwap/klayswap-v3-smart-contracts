// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

contract MockGovernance {

    address public owner;
    address public nextOwner;
    address public executor;

    address public factory;
    address public rewardToken;
    address public vRewardToken;
    address public router;
    address public buyback;
    address public treasury;
    address public governor;
    address public singlePoolTransferStrategy;
    address public rewardTreasury;
    address public v3Factory;

    uint256 public vRewardTokenMiningRate;
    uint256 public treasuryMiningRate;
    uint256 public singlePoolMiningRate;
    uint256 public miningShareRate;
    uint256 public buybackRate;
    uint256 public rateNumerator;

    uint256 public interval;
    uint256 public nextTime;
    uint256 public prevTime;
    uint256 public epoch;

    bool public isInitialized = false;
    bool public entered = false;

    uint256 public transactionCount = 0;
    mapping(uint256 => bool) public transactionExecuted;
    mapping(uint256 => address) public transactionDestination;
    mapping(uint256 => uint256) public transactionValue;
    mapping(uint256 => bytes) public transactionData;

    mapping(uint256 => uint256) public epochMined;
    mapping(address => uint256) public lastEpoch;
    mapping(uint256 => mapping(address => uint256)) public epochRates;

    constructor() {
        owner = msg.sender;
        vRewardTokenMiningRate = 6500;
        treasuryMiningRate = 2000;
        singlePoolMiningRate = 500;
        buybackRate = 20;
        rateNumerator = 1e14;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function version() external pure returns (string memory) {
        return "GovernanceImpl20240528";
    }

    function changeNextOwner(address _nextOwner) external onlyOwner {
        nextOwner = _nextOwner;
    }

    function changeOwner() external {
        require(msg.sender == nextOwner);

        owner = nextOwner;
        nextOwner = address(0);
    }

    function setV2Addresses(
        address _factory,
        address _router,
        address _rewardToken
    ) external onlyOwner {
        factory = _factory;
        router = _router;
        rewardToken = _rewardToken;
    }

    function acceptEpoch() external {
        address pool = msg.sender;

        if (pool == vRewardToken) {
            pool = address(0);
        } else if (pool == singlePoolTransferStrategy) {
            pool = address(1);
        } else if (pool == rewardTreasury) {
            pool = address(2);
        }

        lastEpoch[pool] = epoch;
    }

    // For VotingRewardToken mining, SinglePool mining
    // totalSum = 10000
    function getEpochMining(
        address pool
    )
        external
        pure
        returns (
            uint256 curEpoch,
            uint256 prevEpoch,
            uint256[] memory rates,
            uint256[] memory mined
        )
    {
        require(pool != address(3));

        curEpoch = 0;
        prevEpoch = 0;

        uint256 len = curEpoch - prevEpoch;
        mined = new uint256[](len);
        rates = new uint256[](len);
    }

    // For Liquidity Pool
    // totalSum = 10000 * rateNumerator
    function getBoostingMining(
        address pool
    )
        external
        pure
        returns (
            uint256 curEpoch,
            uint256 prevEpoch,
            uint256[] memory mined,
            uint256[] memory rates
        )
    {
        require(pool > address(3));

        curEpoch = 0;
        prevEpoch = 0;

        uint256 len = curEpoch - prevEpoch;
        mined = new uint256[](len);
        rates = new uint256[](len);

    }
}
