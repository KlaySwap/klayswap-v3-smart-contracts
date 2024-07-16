// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IRewardToken {
    function mined() external view returns (uint256 res);
    function newMined() external view returns (uint256 res);
    function name() external view returns (string memory);
    function sendReward(address user, uint256 amount) external;
    function approve(address _spender, uint256 _value) external returns (bool);
    function totalSupply() external view returns (uint256);
    function claimTeamAward() external;
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool);
    function minableTime() external view returns (uint256);
    function decimals() external view returns (uint8);
    function burn(uint256 amount) external;
    function teamWallet() external view returns (address);
    function changeNextOwner(address _nextOwner) external;
    function changeOwner() external;
    function nextOwner() external view returns (address);
    function balanceOf(address) external view returns (uint256);
    function rewarded() external view returns (uint256);
    function blockAmount() external view returns (uint256);
    function halfLife() external view returns (uint256);
    function miningAmount() external view returns (uint256);
    function setMinableBlock() external;
    function owner() external view returns (address);
    function teamAward() external view returns (uint256);
    function symbol() external view returns (string memory);
    function teamRatio() external view returns (uint256);
    function entered() external view returns (bool);
    function transfer(address _to, uint256 _value) external returns (bool);
    function changeTeamWallet(address _teamWallet) external;
    function getCirculation()
        external
        view
        returns (uint256 blockNumber, uint256 nowCirculation);
    function allowance(address, address) external view returns (uint256);
    function refixMining(uint256 newBlockAmount, uint256 newHalfLife) external;
    function minableBlock() external view returns (uint256);
}
