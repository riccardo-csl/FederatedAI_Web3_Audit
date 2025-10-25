// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FedAggregatorNFT} from "src/smart_contracts/FedAggregator.sol";

contract FedAggregatorBehaviorTest is Test {
    address internal agg = address(0xA11CE);

    function testConstructorSetsOwnerAndState() public {
        FedAggregatorNFT c = new FedAggregatorNFT(agg, "init-hash");
        assertEq(c.owner(), agg);
        assertEq(c.getAggregator(), agg);
        assertEq(c.getCurrentRound(), 0);
        assertEq(c.federatedStatus(), 0);
    }

    function testMintUpdatesStateAndMintsNFT() public {
        FedAggregatorNFT c = new FedAggregatorNFT(agg, "init-hash");
        string memory weights = "w1";
        string memory info = "{\"k\":1}";

        vm.prank(agg);
        c.mint(weights, info);

        assertEq(c.getCurrentRound(), 1);
        assertEq(c.getRoundWeight(1), weights);
        assertEq(c.getRoundHash(1), weights);
        assertEq(c.getRoundDetails(1), info);
        assertEq(c.getModelWeightHash(), weights);
        assertEq(c.ownerOf(1), agg);
        assertEq(c.balanceOf(agg), 1);
    }

    function testEndFederationPreventsFurtherMints() public {
        FedAggregatorNFT c = new FedAggregatorNFT(agg, "init-hash");
        vm.startPrank(agg);
        c.mint("w1", "{}");
        c.endFederation();
        vm.stopPrank();

        vm.prank(agg);
        vm.expectRevert(bytes("Federated process ended"));
        c.mint("w2", "{}");
    }

    function testChangeAggregatorTransfersOwnership() public {
        FedAggregatorNFT c = new FedAggregatorNFT(agg, "init-hash");
        address newAgg = address(0xBEEF);

        vm.prank(agg);
        c.changeAggregator(newAgg);
        assertEq(c.owner(), newAgg);
        assertEq(c.getAggregator(), newAgg);

        // Old owner cannot mint anymore
        vm.prank(agg);
        vm.expectRevert();
        c.mint("wX", "{}");

        // New owner can mint
        vm.prank(newAgg);
        c.mint("w2", "{}");
        assertEq(c.getCurrentRound(), 1);
    }

    function testTransferOwnershipSyncsAggregatorAddress() public {
        FedAggregatorNFT c = new FedAggregatorNFT(agg, "init-hash");
        address newOwner = address(0xD00D);

        vm.prank(agg);
        c.transferOwnership(newOwner);
        assertEq(c.owner(), newOwner);
        assertEq(c.getAggregator(), newOwner);
    }

    function testConstructorGuards() public {
        // Ownable constructor reverts first on zero owner; accept any revert
        vm.expectRevert();
        new FedAggregatorNFT(address(0), "init-hash");

        vm.expectRevert(bytes("Model hash cannot be empty"));
        new FedAggregatorNFT(agg, "");
    }
}

