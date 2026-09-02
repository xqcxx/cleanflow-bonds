// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {CleanFlowController} from "../src/core/CleanFlowController.sol";

/// @notice Permissionless source trigger. Reactive selects clear or finalize from recorded evidence.
contract RequestResolutionScript is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        CleanFlowController controller = CleanFlowController(vm.envAddress("CONTROLLER"));
        bytes32 executionId = vm.envBytes32("EXECUTION_ID");
        vm.startBroadcast(privateKey);
        controller.requestWarrantyResolution(executionId);
        vm.stopBroadcast();
    }
}
