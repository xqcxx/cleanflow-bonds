// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-hooks-public/utils/HookMiner.sol";
import {CleanFlowController} from "../core/CleanFlowController.sol";
import {CleanFlowHook} from "../hook/CleanFlowHook.sol";

contract CleanFlowHookFactory {
    uint160 public constant REQUIRED_FLAGS = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;

    error InvalidHookAddress();

    event HookDeployed(address indexed hook, address indexed router, bytes32 indexed salt);

    function findSalt(IPoolManager poolManager, CleanFlowController controller, address router)
        external
        view
        returns (address predictedHook, bytes32 salt)
    {
        return HookMiner.find(
            address(this),
            REQUIRED_FLAGS,
            type(CleanFlowHook).creationCode,
            abi.encode(poolManager, controller, router)
        );
    }

    function deployHook(
        bytes32 salt,
        IPoolManager poolManager,
        CleanFlowController controller,
        address router
    ) external returns (CleanFlowHook hook) {
        hook = new CleanFlowHook{salt: salt}(poolManager, controller, router);
        if ((uint160(address(hook)) & Hooks.ALL_HOOK_MASK) != REQUIRED_FLAGS) revert InvalidHookAddress();
        emit HookDeployed(address(hook), router, salt);
    }
}
