// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {FedAggregatorNFT} from "src/smart_contracts/FedAggregator.sol"; // resolved via foundry src path

contract DeployAggregator is Script {
    function run() external {
        // Environment vars required: PRIVATE_KEY and MODEL_HASH
        uint256 pk = vm.envUint("PRIVATE_KEY");
        string memory modelHash = vm.envString("MODEL_HASH");

        address aggregator = vm.addr(pk); // owner/governance = deployer

        vm.startBroadcast(pk);
        FedAggregatorNFT agg = new FedAggregatorNFT(aggregator, modelHash);
        vm.stopBroadcast();

        console2.log("FedAggregatorNFT deployed at:", address(agg));
    }
}
