// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FedAggregatorNFT} from "src/smart_contracts/FedAggregator.sol";

contract FedAggregatorTest is Test {
    function testMintIncrementsRound() public {
        address agg = address(0xA11CE);
        FedAggregatorNFT c = new FedAggregatorNFT(agg, "init-hash");

        vm.prank(agg);
        c.mint("weights-1", "{}");

        assertEq(c.getCurrentRound(), 1);
        assertEq(c.getRoundWeight(1), "weights-1");
    }
}

