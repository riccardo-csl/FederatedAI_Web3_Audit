// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FedPeerNFT is ERC721, Ownable {
    // Public state for auditability
    address public peerAddress;               // peer address (also owner)
    address public aggregatorAddress;         // aggregator contract address
    uint256 public lastParticipatedRound;     // last round this peer participated in
    uint8   public peerStatus;                // 0 = active, 1 = inactive

    // Per-round auditing (JSON with peer hash/metrics for that round)
    mapping(uint256 => string) public roundDetails;

    // Events
    event PeerMinted(uint256 indexed roundNumber, string payload);
    event PeerStatusChanged(uint8 status);

    constructor(address _peerAddress, address _aggregatorAddress)
        ERC721("FedPeerNFT", "FPN")
        Ownable(_peerAddress) // owner = peer (so it can call mint)
    {
        require(_peerAddress != address(0), "Peer address cannot be zero");
        require(_aggregatorAddress != address(0), "Aggregator address cannot be zero");
        peerAddress = _peerAddress;
        aggregatorAddress = _aggregatorAddress;
        peerStatus = 0; // active
        lastParticipatedRound = 0; // before participation
    }

    // Convenience getters
    function getPeerStatus() external view returns (uint8) { return peerStatus; }
    function getPeerAddress() external view returns (address) { return peerAddress; }
    function getAggregatorAddress() external view returns (address) { return aggregatorAddress; }
    function getLastParticipatedRound() external view returns (uint256) { return lastParticipatedRound; }

    /// @notice Register the peer participation in a round and mint the NFT (tokenId = roundNumber).
    /// @dev `payload` can be a JSON with {peer_id, round, weight_hash, test_accuracy, ...}
    function mint(uint256 roundNumber, string memory payload) external onlyOwner {
        require(peerStatus == 0, "Peer is not active");
        require(roundNumber > 0, "Round must be >= 1");
        // If you want to allow gaps, use >. For strict sequence, use == lastParticipatedRound+1.
        require(roundNumber > lastParticipatedRound, "Invalid round number");

        // Persistence for auditing
        roundDetails[roundNumber] = payload;
        lastParticipatedRound = roundNumber;

        // Mint 1 NFT to the peer (tokenId = round number)
        _safeMint(peerAddress, roundNumber);

        emit PeerMinted(roundNumber, payload);
    }

    /// @notice Deactivate the peer (aggregator only).
    function stopPeer() external {
        require(msg.sender == aggregatorAddress, "Only aggregator can stop the peer");
        peerStatus = 1;
        emit PeerStatusChanged(peerStatus);
    }

    /// @notice Reactivate the peer (aggregator only).
    function restartPeer() external {
        require(msg.sender == aggregatorAddress, "Only aggregator can restart the peer");
        peerStatus = 0;
        emit PeerStatusChanged(peerStatus);
    }

    /// @notice Keep `owner()` and `peerAddress` synchronized when ownership changes.
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        super.transferOwnership(newOwner);
        peerAddress = newOwner;
    }

    function supportsInterface(bytes4 interfaceId)
        public view virtual override(ERC721) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
