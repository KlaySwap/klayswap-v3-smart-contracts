// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../core/libraries/LowGasSafeMath.sol';
import '../interfaces/IV2Factory.sol';
import '../interfaces/IExchange.sol';
import './interfaces/IV3Migrator.sol';
import './interfaces/external/IWETH9.sol';
import './interfaces/INonfungiblePositionManager.sol';
import './libraries/TransferHelper.sol';
import './base/PeripheryImmutableState.sol';
import './base/Multicall.sol';
import './base/SelfPermit.sol';
import './base/PoolInitializer.sol';

library Balance {
    using LowGasSafeMath for uint256;
    function balance(address t) internal view returns (uint256) {
        return (t == address(0)) ? address(this).balance : IERC20(t).balanceOf(address(this));
    }

    function balanceSub(address t, uint256 amount) internal view returns (uint256) {
        return (t == address(0)) ? address(this).balance.sub(amount) : IERC20(t).balanceOf(address(this)).sub(amount);
    }
}

/// @title Uniswap V3 Migrator
contract V3Migrator is IV3Migrator, PeripheryImmutableState, PoolInitializer, Multicall, SelfPermit {
    using LowGasSafeMath for uint256;

    event ChangeNextOwner(address nextOwner);
    event ChangeOwner(address owner);

    address public owner;
    address public nextOwner;
    address public immutable v2Factory;
    address public immutable nonfungiblePositionManager;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function changeNextOwner(address _nextOwner) external onlyOwner {
        nextOwner = _nextOwner;

        emit ChangeNextOwner(nextOwner);
    }

    function changeOwner() external {
        require(msg.sender == nextOwner);

        owner = nextOwner;
        nextOwner = address(0);

        emit ChangeOwner(owner);
    }

    function version() public pure returns (string memory) {
        return "V3Migrator20240528";
    }

    constructor(
        address _factory,
        address _WETH9,
        address _nonfungiblePositionManager,
        address _v2Factory
    ) PeripheryImmutableState(_factory, _WETH9) {
        owner = msg.sender;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        v2Factory = _v2Factory;
    }

    receive() external payable {
        require(msg.sender == WETH9 || IV2Factory(v2Factory).poolExist(msg.sender));
    }

    function migrate(MigrateParams calldata params) external override {
        require(params.percentageToMigrate > 0, 'Percentage too small');
        require(params.percentageToMigrate <= 100, 'Percentage too large');

        uint256 amount0V2;
        uint256 amount1V2;
        // burn v2 liquidity to this address
        IExchange(params.pair).transferFrom(msg.sender, address(this), params.liquidityToMigrate);

        {
            address token0 = IExchange(params.pair).token0();
            address token1 = IExchange(params.pair).token1();
            uint256 bal0 = Balance.balance(token0);
            uint256 bal1 = Balance.balance(token1);

            IExchange(params.pair).removeLiquidityWithLimit(params.liquidityToMigrate, 1, 1, address(this));

            bal0 = Balance.balanceSub(token0, bal0);
            bal1 = Balance.balanceSub(token1, bal1);

            if (token0 < token1) {
                require(token0 == params.token0);
                require(token1 == params.token1);
                (amount0V2, amount1V2) = (bal0, bal1);
            } else {
                require(token1 == params.token0);
                require(token0 == params.token1);
                (amount0V2, amount1V2) = (bal1, bal0);
            }
        }
        // calculate the amounts to migrate to v3
        uint256 amount0V2ToMigrate = amount0V2.mul(params.percentageToMigrate) / 100;
        uint256 amount1V2ToMigrate = amount1V2.mul(params.percentageToMigrate) / 100;

        // approve the position manager up to the maximum token amounts
        TransferHelper.safeApprove(params.token0, nonfungiblePositionManager, amount0V2ToMigrate);
        TransferHelper.safeApprove(params.token1, nonfungiblePositionManager, amount1V2ToMigrate);

        // mint v3 position
        (, , uint256 amount0V3, uint256 amount1V3) =
            INonfungiblePositionManager(nonfungiblePositionManager).mint(
                INonfungiblePositionManager.MintParams({
                    token0: params.token0,
                    token1: params.token1,
                    fee: params.fee,
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    amount0Desired: amount0V2ToMigrate,
                    amount1Desired: amount1V2ToMigrate,
                    amount0Min: params.amount0Min,
                    amount1Min: params.amount1Min,
                    recipient: params.recipient,
                    deadline: params.deadline
                })
            );

        // if necessary, clear allowance and refund dust
        if (amount0V3 < amount0V2) {
            if (amount0V3 < amount0V2ToMigrate) {
                TransferHelper.safeApprove(params.token0, nonfungiblePositionManager, 0);
            }

            uint256 refund0 = amount0V2 - amount0V3;
            if (params.refundAsETH && params.token0 == WETH9) {
                IWETH9(WETH9).withdraw(refund0);
                TransferHelper.safeTransferETH(msg.sender, refund0);
            } else {
                TransferHelper.safeTransfer(params.token0, msg.sender, refund0);
            }
        }

        if (amount1V3 < amount1V2) {
            if (amount1V3 < amount1V2ToMigrate) {
                TransferHelper.safeApprove(params.token1, nonfungiblePositionManager, 0);
            }

            uint256 refund1 = amount1V2 - amount1V3;
            if (params.refundAsETH && params.token1 == WETH9) {
                IWETH9(WETH9).withdraw(refund1);
                TransferHelper.safeTransferETH(msg.sender, refund1);
            } else {
                TransferHelper.safeTransfer(params.token1, msg.sender, refund1);
            }
        }
    }

    function inCaseTokensGetStuck(address token, uint256 amount) external onlyOwner {
        if(token == address(0)){
            require(address(this).balance >= amount);
            TransferHelper.safeTransferETH(owner, amount);
        }
        else {
            require(IERC20(token).balanceOf(address(this)) >= amount);
            TransferHelper.safeTransfer(token, owner, amount);
        }
    }
}
