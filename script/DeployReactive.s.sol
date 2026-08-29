// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {CleanFlowRSC} from "../src/reactive/CleanFlowRSC.sol";

contract DeployReactiveScript is Script {
    function run() external returns (CleanFlowRSC rsc) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        uint256 originChainId = vm.envUint("ORIGIN_CHAIN_ID");
        uint256 destinationChainId = vm.envUint("DESTINATION_CHAIN_ID");
        address hook = vm.envAddress("HOOK");
        address controller = vm.envAddress("CONTROLLER");
        uint64 gasLimit = uint64(vm.envOr("CALLBACK_GAS_LIMIT", uint256(1_000_000)));
        uint256 subscriptionFunding = vm.envOr("SUBSCRIPTION_FUNDING", uint256(0.1 ether));

        vm.startBroadcast(privateKey);
        rsc = new CleanFlowRSC{value: subscriptionFunding}(
            originChainId,
            destinationChainId,
            hook,
            controller,
            controller,
            gasLimit,
            1e15
        );
        vm.stopBroadcast();

        string memory root = "deployment";
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "originChainId", originChainId);
        vm.serializeUint(root, "destinationChainId", destinationChainId);
        vm.serializeAddress(root, "hook", hook);
        vm.serializeAddress(root, "controller", controller);
        string memory json = vm.serializeAddress(root, "rsc", address(rsc));
        vm.writeJson(json, "deployments/reactive-lasna.json");
    }
}
