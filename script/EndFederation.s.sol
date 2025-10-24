// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {FedAggregatorNFT} from "src/smart_contracts/FedAggregator.sol";

contract EndFederation is Script {
    function run() external {
        // Required env:
        // PRIVATE_KEY: aggregator key (contract owner)
        // AGGREGATOR_ADDRESS: aggregator contract address
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address aggregatorAddr = vm.envAddress("AGGREGATOR_ADDRESS");

        FedAggregatorNFT agg = FedAggregatorNFT(aggregatorAddr);

        vm.startBroadcast(pk);
        agg.endFederation();
        vm.stopBroadcast();

        console2.log("Federation ended at round:", agg.getCurrentRound());
    }
}
