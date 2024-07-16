// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

interface IV3Treasury {
    function _initialize(address _owner, address _factory) external;
    function changeNextOwner(address _nextOwner) external;
    function changeOwner() external;
    function create(
        address token,
        address pool,
        uint256 amount,
        uint256 blockAmount,
        uint256 blockNumber
    ) external;
    function deployAirdropOperator(
        address token,
        address pool
    ) external returns (address operator);
    function deployedOperator(address) external view returns (bool);
    function deposit(address token, address pool, uint256 amount) external;
    function distributionCount(address) external view returns (uint256);
    function distributionEntries(
        address,
        uint256
    ) external view returns (bytes32);
    function distributions(
        bytes32
    )
        external
        view
        returns (
            address operator,
            address token,
            uint256 totalAmount,
            uint256 blockAmount,
            uint256 distributableBlock,
            uint256 distributedAmount,
            uint256 calcAmount
        );
    function entered() external view returns (bool);
    function factory() external view returns (address);
    function getAirdropAmount()
        external
        returns (uint256 amount0, uint256 amount1);
    function getDistributionInfo(
        bytes32 id
    )
        external
        view
        returns (
            uint256 totalAmount,
            uint256 blockAmount,
            uint256 distributableBlock,
            uint256 endBlock,
            uint256 distributed
        );
    function getPoolAirdropAmount(
        address pool
    ) external view returns (uint256 amount0, uint256 amount1);
    function nextOwner() external view returns (address);
    function owner() external view returns (address);
    function policyAdmin() external view returns (address);
    function refixBlockAmount(
        address token,
        address pool,
        uint256 blockAmount
    ) external;
    function setOperator(address _operator, bool _valid) external;
    function setPolicyAdmin(address _policyAdmin) external;
    function setValidOperatorList(address[] calldata operators) external;
    function validOperator(address) external view returns (bool);
    function version() external pure returns (string memory);
}
