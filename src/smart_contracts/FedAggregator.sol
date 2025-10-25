// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FedAggregatorNFT is ERC721, Ownable {
    // Public state for auditability
    string public modelHash;           // initial model hash
    string public modelWeightHash;     // latest aggregated weights hash
    uint256 public currentRound;       // 1-based: 0 -> before federation, 1 after first mint
    uint8   public federatedStatus;    // 0=in progress, 1=ended
    address public aggregatorAddress;  // aggregator governance address

    // Per-round audit history
    mapping(uint256 => string) public roundHashes;   // optional: alias/compatibility
    mapping(uint256 => string) public roundDetails;  // JSON with round metrics/metadata
    mapping(uint256 => string) public roundWeights;  // aggregated weights hash per round

    event AggregatorRoundMinted(uint256 indexed roundNumber, string modelWeightsHash, string roundInfo);
    event FederationEnded(uint256 finalRound);

    constructor(address _aggregatorAddress, string memory _modelHash)
        ERC721("FedAggregatorNFT", "FAN")
        Ownable(_aggregatorAddress)                 // owner = aggregator
    {
        require(_aggregatorAddress != address(0), "Aggregator cannot be zero address");
        require(bytes(_modelHash).length > 0, "Model hash cannot be empty");
        aggregatorAddress = _aggregatorAddress;
        modelHash = _modelHash;
        currentRound = 0;                           // starts at 0: first mint sets it to 1
        federatedStatus = 0;                        // in progress
    }

    // Convenience getters
    function getAggregator() external view returns (address) { return aggregatorAddress; }
    function getModelWeightHash() external view returns (string memory) { return modelWeightHash; }
    function getCurrentRound() external view returns (uint256) { return currentRound; }
    function getRoundHash(uint256 roundNumber) external view returns (string memory) { return roundHashes[roundNumber]; }
    function getRoundDetails(uint256 roundNumber) external view returns (string memory) { return roundDetails[roundNumber]; }
    function getRoundWeight(uint256 roundNumber) external view returns (string memory) { return roundWeights[roundNumber]; }

    /// @notice Register a new federated round (1 NFT per round, tokenId = roundNumber).
    /// @param modelWeightsHash keccak256 hash of aggregated round weights
    /// @param roundInfo JSON string with metadata (timestamp, duration, avg acc, etc.)
    function mint(string memory modelWeightsHash, string memory roundInfo) external onlyOwner {
        require(federatedStatus == 0, "Federated process ended");
        require(bytes(modelWeightsHash).length > 0, "Model weights hash cannot be empty");

        // 1) increment round (1-based)
        unchecked { currentRound += 1; }           // 0 -> 1 on first mint

        // 2) persistence for audit
        roundWeights[currentRound] = modelWeightsHash;
        roundHashes[currentRound]  = modelWeightsHash; // optional alias
        roundDetails[currentRound] = roundInfo;
        modelWeightHash = modelWeightsHash;

        // 3) mint 1 NFT for this round to the aggregator (tokenId = currentRound)
        _safeMint(aggregatorAddress, currentRound);

        emit AggregatorRoundMinted(currentRound, modelWeightsHash, roundInfo);
    }

    /// @notice End the federation (prevents further mints).
    function endFederation() external onlyOwner {
        federatedStatus = 1;
        emit FederationEnded(currentRound);
    }

    /// @notice Update the aggregator and transfer ownership for consistency.
    function changeAggregator(address newAggregator) external onlyOwner {
        require(newAggregator != address(0), "New aggregator cannot be zero address");
        aggregatorAddress = newAggregator;
        _transferOwnership(newAggregator);          // keep owner/aggregator in sync
    }

    /// @notice Keep `owner()` and `aggregatorAddress` synchronized when ownership changes.
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        super.transferOwnership(newOwner);
        aggregatorAddress = newOwner;
    }

    function supportsInterface(bytes4 interfaceId)
        public view virtual override(ERC721) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
