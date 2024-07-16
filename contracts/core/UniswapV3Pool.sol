// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

interface ImplGetter {
    function poolImplementation() external view returns (address);
}

contract UniswapV3Pool {
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    constructor() {
        assert(_ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        _setOwner(msg.sender);

        address impl = ImplGetter(_owner()).poolImplementation();
        (bool success, ) = impl.delegatecall(abi.encodeWithSignature("__UniswapV3Pool_init()"));
        require(success);
    }

    event OwnerChanged(address previousOwner, address newOwner);

    modifier onlyOwner {
        require(msg.sender == _owner());
        _;
    }

    function Owner() external view returns (address) {
        return _owner();
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
        address impl = ImplGetter(_owner()).poolImplementation();
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