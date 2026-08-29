// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {CleanFlowController} from "../src/core/CleanFlowController.sol";

contract ConfigureRvmScript is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        CleanFlowController controller = CleanFlowController(vm.envAddress("CONTROLLER"));
        address rvmId = vm.envAddress("REACTIVE_RVM_ID");
        vm.startBroadcast(privateKey);
        controller.setExpectedRvmId(rvmId);
        vm.stopBroadcast();
    }
}
