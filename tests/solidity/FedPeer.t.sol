// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FedPeerNFT} from "src/smart_contracts/FedPeer.sol";

contract FedPeerTest is Test {
    address internal aggregator = address(0xA11CE);
    address internal peer = address(0xB0B);

    function testConstructorInitialState() public {
        FedPeerNFT c = new FedPeerNFT(peer, aggregator);
        assertEq(c.owner(), peer);
        assertEq(c.getPeerAddress(), peer);
        assertEq(c.getAggregatorAddress(), aggregator);
        assertEq(c.getPeerStatus(), 0);
        assertEq(c.getLastParticipatedRound(), 0);
    }

    function testMintStoresPayloadAndMintsToken() public {
        FedPeerNFT c = new FedPeerNFT(peer, aggregator);
        string memory payload = "{\"peer_id\":1,\"round\":1,\"weight_hash\":\"w\"}";

        vm.prank(peer);
        c.mint(1, payload);

        assertEq(c.getLastParticipatedRound(), 1);
        assertEq(c.roundDetails(1), payload);
        assertEq(c.ownerOf(1), peer);
        assertEq(c.balanceOf(peer), 1);
    }

    function testMintOnlyOwner() public {
        FedPeerNFT c = new FedPeerNFT(peer, aggregator);
        vm.expectRevert();
        c.mint(1, "{}" );
    }

    function testMintInvalidRoundReverts() public {
        FedPeerNFT c = new FedPeerNFT(peer, aggregator);
        vm.prank(peer);
        vm.expectRevert(bytes("Round must be >= 1"));
        c.mint(0, "{}");

        vm.prank(peer);
        c.mint(1, "{}");

        vm.prank(peer);
        vm.expectRevert(bytes("Invalid round number"));
        c.mint(1, "{}");
    }

    function testStopAndRestartPeer() public {
        FedPeerNFT c = new FedPeerNFT(peer, aggregator);

        // Only aggregator can stop/restart
        vm.prank(peer);
        vm.expectRevert(bytes("Only aggregator can stop the peer"));
        c.stopPeer();

        vm.prank(aggregator);
        c.stopPeer();
        assertEq(c.getPeerStatus(), 1);

        // Cannot mint while inactive
        vm.prank(peer);
        vm.expectRevert(bytes("Peer is not active"));
        c.mint(1, "{}");

        vm.prank(aggregator);
        c.restartPeer();
        assertEq(c.getPeerStatus(), 0);

        vm.prank(peer);
        c.mint(1, "{}");
        assertEq(c.getLastParticipatedRound(), 1);
    }

    function testTransferOwnershipSyncsPeerAddress() public {
        FedPeerNFT c = new FedPeerNFT(peer, aggregator);
        address newPeer = address(0xCAFE);
        vm.prank(peer);
        c.transferOwnership(newPeer);
        assertEq(c.owner(), newPeer);
        assertEq(c.getPeerAddress(), newPeer);
    }
}

