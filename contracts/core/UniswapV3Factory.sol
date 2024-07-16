// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import '@openzeppelin/contracts/utils/Address.sol';

/// @title Canonical Uniswap V3 factory
/// @notice Deploys Uniswap V3 pools and manages ownership and control over pool protocol fees
contract UniswapV3Factory {
    // Impl Owner
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    // Factory Impl
    bytes32 private constant _IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    // Pool Impl
    bytes32 private constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50 ;

    constructor(
        address payable _impl,
        address payable _poolImpl,
        address _governance,
        address _WETH
    ) {
        _setOwner(msg.sender);

        _setImplementation(_impl);
        _setPoolImplementation(_poolImpl);

        (bool success, ) = _impl.delegatecall(abi.encodeWithSignature("_initialize(address,address)", _governance, _WETH));
        require(success);
    }

    event OwnerChanged(address previousOwner, address newOwner);
    event Upgraded(address implementation);

    modifier onlyOwner {
        require(msg.sender == _owner());
        _;
    }

    function Owner() external view returns (address) {
        return _owner();
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    function poolImplementation() external view returns (address) {
        return _poolImplementation();
    }

    function _setImplementation(address payable _newImp) public onlyOwner {
        bytes32 slot = _IMPL_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _newImp)
        }
    }

    function _setImplementationAndCall(address payable _newImp, bytes calldata data) public onlyOwner {
        bytes32 slot = _IMPL_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _newImp)
        }

        if (data.length > 0) {
            Address.functionDelegateCall(_newImp, data);
        }
    }

    function _setPoolImplementation(address payable _newImp) public onlyOwner {
        bytes32 slot = _BEACON_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _newImp)
        }
    }

    function _implementation() internal view returns (address adm) {
        bytes32 slot = _IMPL_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            adm := sload(slot)
        }
    }

    function _poolImplementation() internal view returns (address adm) {
        bytes32 slot = _BEACON_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            adm := sload(slot)
        }
    }

    function _owner() internal view returns (address adm) {
        bytes32 slot = _ADMIN_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            adm := sload(slot)
        }
    }

    function _setOwner(address newOwner) private {
        bytes32 slot = _ADMIN_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, newOwner)
        }
    }

    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Proxy: new Owner is the zero address");
        emit OwnerChanged(_owner(), newOwner);
        _setOwner(newOwner);
    }

    function _delegate() internal {
        address impl = _implementation();
        require(impl != address(0));
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    fallback() external payable virtual {
        _delegate();
    }

    receive() external payable virtual {
        _delegate();
    }
}