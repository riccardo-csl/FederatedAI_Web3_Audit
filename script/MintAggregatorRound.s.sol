// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {FedAggregatorNFT} from "src/smart_contracts/FedAggregator.sol";

contract MintAggregatorRound is Script {
    function run() external {
        // Required env:
        // PRIVATE_KEY: aggregator key (contract owner)
        // AGGREGATOR_ADDRESS: aggregator contract address
        // MODEL_WEIGHTS_HASH: hash string of aggregated weights for the round
        // ROUND_INFO: JSON string with metadata (e.g., "{}")
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address aggregatorAddr = vm.envAddress("AGGREGATOR_ADDRESS");
        string memory weights = vm.envString("MODEL_WEIGHTS_HASH");
        string memory info = vm.envString("ROUND_INFO");

        FedAggregatorNFT agg = FedAggregatorNFT(aggregatorAddr);

        vm.startBroadcast(pk);
        agg.mint(weights, info);
        vm.stopBroadcast();

        console2.log("Minted round:", agg.getCurrentRound());
    }
}
