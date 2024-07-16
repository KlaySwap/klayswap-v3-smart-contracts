// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../core/interfaces/IERC20Minimal.sol';
import '../core/interfaces/IUniswapV3Factory.sol';
import './interfaces/IV3Treasury.sol';

contract V3AirdropOperator {
    address public owner;
    address public nextOwner;

    IV3Treasury public treasury;
    IUniswapV3Factory public factory;

    address immutable public token;
    address immutable public pool;
    bool internal initialized;

    constructor(address _owner, address _token, address _pool) {
        owner = _owner;

        treasury = IV3Treasury(msg.sender);
        factory = IUniswapV3Factory(treasury.factory());
        token = _token;
        pool = _pool;
    }

    function version() external pure returns (string memory) {
        return "V3AirdropOperator20240528";
    }

    // ======================= owner method ===========================

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function changeNextOwner(address _nextOwner) external onlyOwner {
        nextOwner = _nextOwner;
    }

    function changeOwner() external {
        require(msg.sender == nextOwner);

        owner = nextOwner;
        nextOwner = address(0);
    }

    // ====================== Stat ====================================

    /// @return totalAmount total airdrop distribution amount
    /// @return blockAmount distributed amount per block
    /// @return distributableBlock block that last claimed
    /// @return endBlock block where the airdrop ends
    /// @return distributed amounts of tokens distributed
    /// @return remain amounts of tokens not distributed yet
    /// @return created isInitialized
    function getAirdropStat() external view returns (
        uint256 totalAmount,
        uint256 blockAmount,
        uint256 distributableBlock,
        uint256 endBlock,
        uint256 distributed,
        uint256 remain,
        bool created
    ) {
        (totalAmount, blockAmount, distributableBlock, endBlock, distributed)
            = treasury.getDistributionInfo(getDistributionId());
        remain = totalAmount - distributed;
        created = initialized;
    }

    /// @return id ID of this operator's airdrop
    function getDistributionId() public view returns (bytes32 id) {
        id = keccak256(abi.encode(address(this), token, pool));
    }

    // ===================== Airdrop method ===========================
    /// @param totalAmount total amount of tokens to be distributed
    /// @param blockAmount amount of tokens to be distributed per block
    /// @param startBlock block number to airdrop start
    function createDistribution(
        uint256 totalAmount,
        uint256 blockAmount,
        uint256 startBlock
    ) external onlyOwner {
        require(IERC20Minimal(token).balanceOf(address(this)) >= totalAmount);
        require(IERC20Minimal(token).approve(address(treasury), totalAmount));

        treasury.create(token, pool, totalAmount, blockAmount, startBlock);
        initialized = true;
    }

    /// @notice Airdrop token deposit
    /// @param amount amount of airdrop token to deposit
    function deposit(uint256 amount) external onlyOwner {
        require(initialized);
        require(amount != 0);

        require(IERC20Minimal(token).balanceOf(address(this)) >= amount);
        require(IERC20Minimal(token).approve(address(treasury), amount));
        treasury.deposit(token, pool, amount);
    }

    /// @notice Airdrop amount per block modification function
    /// The function is applied immediately from the called block
    /// @param blockAmount airdrop block amount to change
    function refixBlockAmount(uint256 blockAmount) external onlyOwner {
        require(initialized);
        require(blockAmount != 0);

        treasury.refixBlockAmount(token, pool, blockAmount);
    }

    /// @notice withdraw tokens remaining in the operator contract
    /// @param _token token address to withdraw
    function withdraw(address _token) external onlyOwner {
        uint256 balance;
        if (_token == address(0)) {
            balance = (address(this)).balance;
            if (balance != 0) {
                (bool res, ) = owner.call{value: balance}("");
                require(res);
            }
        } else {
            balance = IERC20Minimal(_token).balanceOf(address(this));
            if (balance != 0) {
                require(IERC20Minimal(_token).transfer(owner, balance));
            }
        }
    }
}
