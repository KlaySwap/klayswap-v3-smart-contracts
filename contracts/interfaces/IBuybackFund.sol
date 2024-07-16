// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IBuybackFund {
    function paths(address, uint256) external view returns (address);
    function changeNextOwner(address _nextOwner) external;
    function monthlyBoostingBurnt(
        address,
        uint256
    ) external view returns (uint256);
    function totalDailyBurnt(uint256) external view returns (uint256);
    function totalWeeklyBoostingBurnt(uint256) external view returns (uint256);
    function getTotalBurnt(
        uint256 epoch
    ) external view returns (uint256 weekly, uint256 biweekly, uint256 monthly);
    function estimateBuybackMining(
        address pool,
        uint256 epoch,
        uint256 rate
    ) external view returns (uint256);
    function weeklyBoostingBurnt(
        address,
        uint256
    ) external view returns (uint256);
    function getBuybackMining(
        address pool,
        uint256 epoch,
        uint256 rate
    ) external view returns (uint256);
    function getBuybackPath(
        address token
    ) external view returns (address[] memory path);
    function setValidOperator(address operator, bool valid) external;
    function setToken(
        address token,
        bool valid,
        address[] calldata path
    ) external;
    function version() external pure returns (string memory);
    function governance() external view returns (address);
    function implementation() external view returns (address);
    function changeOwner() external;
    function buyback(
        address pool,
        uint256 minAmount0,
        uint256 minAmount1
    ) external;
    function nextOwner() external view returns (address);
    function getPoolBurnt(
        address pool,
        uint256 epoch
    ) external view returns (uint256 weekly, uint256 biweekly, uint256 monthly);
    function validOperator(address) external view returns (bool);
    function emergencyWithdraw(address token) external;
    function _setImplementation(address _newImp, string calldata) external;
    function buybackRange(
        uint256 si,
        uint256 ei,
        uint256[] calldata minAmount0,
        uint256[] calldata minAmount1
    ) external;
    function forceUpdateBoostingBurnt(address[] calldata pools) external;
    function epochBurnt(uint256) external view returns (bool);
    function owner() external view returns (address);
    function updateFund0(uint256 amount) external;
    function buybackPools(
        address[] calldata pools,
        uint256[] calldata minAmount0,
        uint256[] calldata minAmount1
    ) external;
    function fund1(address) external view returns (uint256);
    function biweeklyBoostingBurnt(
        address,
        uint256
    ) external view returns (uint256);
    function entered() external view returns (bool);
    function factory() external view returns (address);
    function fund0(address) external view returns (uint256);
    function validToken(address) external view returns (bool);
    function totalMonthlyBoostingBurnt(uint256) external view returns (uint256);
    function epochBurn() external;
    function dailyBurnt(address, uint256) external view returns (uint256);
    function totalBiweeklyBoostingBurnt(
        uint256
    ) external view returns (uint256);
    function rewardToken() external view returns (address);
    function router() external view returns (address);
    function updateFund1(uint256 amount) external;
}
