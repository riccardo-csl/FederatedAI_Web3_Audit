// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {FedPeerNFT} from "src/smart_contracts/FedPeer.sol";

contract DeployPeer is Script {
    function run() external {
        // Required env:
        // PRIVATE_KEY: deployer key (can be aggregator/admin)
        // PEER_ADDRESS: peer EOA (will become contract owner)
        // AGGREGATOR_ADDRESS: aggregator contract address
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address peer = vm.envAddress("PEER_ADDRESS");
        address aggregator = vm.envAddress("AGGREGATOR_ADDRESS");

        vm.startBroadcast(pk);
        FedPeerNFT peerNft = new FedPeerNFT(peer, aggregator);
        vm.stopBroadcast();

        console2.log("FedPeerNFT deployed at:", address(peerNft));
    }
}
