// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {FedPeerNFT} from "src/smart_contracts/FedPeer.sol";

contract MintPeerParticipation is Script {
    function run() external {
        // Required env:
        // PRIVATE_KEY: peer key (owner of the peer contract)
        // PEER_CONTRACT_ADDRESS: FedPeerNFT contract address
        // ROUND_NUMBER: round number (>=1)
        // PAYLOAD: JSON string with metadata
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address peerContract = vm.envAddress("PEER_CONTRACT_ADDRESS");
        uint256 roundNumber = vm.envUint("ROUND_NUMBER");
        string memory payload = vm.envString("PAYLOAD");

        FedPeerNFT peer = FedPeerNFT(peerContract);

        vm.startBroadcast(pk);
        peer.mint(roundNumber, payload);
        vm.stopBroadcast();

        console2.log("Peer last round:", peer.getLastParticipatedRound());
    }
}
