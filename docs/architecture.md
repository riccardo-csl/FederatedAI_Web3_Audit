
# System Architecture – Federated AI Web3 Auditing

This document provides a rigorous, end‑to‑end description of the system architecture, the on‑chain and off‑chain components, and how the Python layer (training + Web3) interacts with the Solidity contracts. The goal is auditable federated learning: each global round and each peer’s participation are anchored on‑chain via deterministic weight hashes and compact, verifiable metadata.

## Goals and Principles
- End‑to‑end auditability for FL rounds and peer participations.
- Minimal on‑chain footprint: only hashes and compact JSON; never raw weights or datasets.
- Determinism and verifiability: Keccak‑256 over flattened/concatenated weights; compact JSON with stable key order.
- Practical developer experience: local Anvil network, Foundry for build/deploy/test, Makefile and helper scripts.

## High‑Level View
The architecture is composed of three layers:
- On‑chain layer (EVM): two ERC‑721 contracts (NFTs) serve as the audit registry for Aggregator and Peer.
- ML orchestration layer (Python): trains clients, applies FedAvg, evaluates, computes hashes, and writes artifacts on‑chain.
- Tooling/DevOps: Foundry (forge, cast, anvil), Makefile, deploy/mint scripts, and verification tools.

## On‑Chain Layer (Solidity)
Two ERC‑721 contracts keep an immutable audit trail as one NFT “per round,” with public state and mappings for introspection.

### FedAggregatorNFT
- Role: global registry of federation rounds. The `Ownable` owner is the aggregator’s governance address.
- Public state (auditable):
  - `modelHash`: initial model hash (e.g., baseline) set at deployment.
  - `modelWeightHash`: latest aggregated weight hash.
  - `currentRound`: 1‑based global round counter (0 before the first mint).
  - `federatedStatus`: 0=in progress, 1=ended.
  - `aggregatorAddress`: governance address (kept in sync with `owner()`).
- Per‑round storage:
  - `roundWeights[round]`: aggregated weight hash for the round.
  - `roundHashes[round]`: alias for compatibility (same value as `roundWeights`).
  - `roundDetails[round]`: compact JSON string with round metadata.
- Events:
  - `AggregatorRoundMinted(roundNumber, modelWeightsHash, roundInfo)`
  - `FederationEnded(finalRound)`
- Key operations:
  - `mint(modelWeightsHash, roundInfo)`: onlyOwner; increments `currentRound`, persists hash and JSON, and mints 1 NFT to the aggregator with `tokenId = currentRound`.
  - `endFederation()`: onlyOwner; sets `federatedStatus=1` to block further mints.
  - `changeAggregator(newAggregator)`: onlyOwner; updates governance and transfers ownership to keep state consistent.
  - `transferOwnership(newOwner)`: override to keep `aggregatorAddress` synchronized with `owner()`.

Operational invariants:
- Exactly one NFT per global round; `tokenId` equals the round number.
- Public getters and state enable straightforward off‑chain audit.

### FedPeerNFT
- Role: captures a single peer’s participation per round. Each mint records the peer payload for that round.
- Public state (auditable):
  - `peerAddress`: peer EOA (also contract owner).
  - `aggregatorAddress`: associated Aggregator contract address.
  - `lastParticipatedRound`: last round the peer participated in.
  - `peerStatus`: 0=active, 1=inactive.
- Per‑round storage:
  - `roundDetails[round]`: peer JSON payload (e.g., `{peer_id, round, weight_hash, test_accuracy, ...}`).
- Events:
  - `PeerMinted(roundNumber, payload)`
  - `PeerStatusChanged(status)`
- Key operations:
  - `mint(roundNumber, payload)`: onlyOwner; persists payload, updates `lastParticipatedRound`, and mints 1 NFT to the peer with `tokenId = roundNumber`. Requires `roundNumber > lastParticipatedRound` to avoid duplicates/backfills.
  - `stopPeer()` / `restartPeer()`: aggregator‑only; disables/enables minting from the peer.
  - `transferOwnership(newOwner)`: override to keep `peerAddress` synchronized with `owner()`.

Operational invariants:
- One NFT for the peer’s participation in a given round (same `tokenId` = round).
- Aggregator can temporarily suspend/reactivate the peer.

## Data Formats and Hashing
The system stores no weights or raw data on‑chain. Instead it uses:
- Keccak‑256 over concatenated weights: deterministic and verifiable off‑chain.
- Compact JSON (no spaces) to enable exact string‑level comparisons against on‑chain storage.

Primary formats:
- Peer payload (for `FedPeerNFT.mint`):
  - `{"peer_id": <int>, "round": <int>, "weight_hash": <hex>, "test_accuracy": <float>}`
- Aggregator round details (for `FedAggregatorNFT.mint`):
  - `{"round_id": <int>, "timestamp": <RFC3339Z>, "duration_sec": <float>, "participants": <int>, "local_epochs": 1, "batch_size": <int>, "avg_round_accuracy": <float>, "lr": <float>}`

Both are produced in compact form (no spaces after commas or colons) to ensure stable comparisons.

## Python Layer (Orchestration + Web3)
The Python layer implements training, hashing, on‑chain interaction, and post‑write verification.

Main components:
- `federated.training_orchestrator.run_federated(...)`:
  - Loads MNIST and splits it across `num_clients`.
  - Builds a Keras model per client, trains 1 epoch, computes accuracy and weight hash for each peer.
  - Applies layer‑wise FedAvg, updates local models, and evaluates globally.
  - For each peer: writes on‑chain (peer mint) with idempotence (checks `lastParticipatedRound`).
  - Aggregator mints the global round with aggregated hash and round JSON.
  - Performs on‑chain read‑backs to assert consistency: `currentRound`, `roundDetails`, and `roundWeight`/`roundHash` must match local values.
- `federated.blockchain_connector.Web3Connector`:
  - Connects to `WEB3_HTTP_PROVIDER` and loads keys, addresses, and ABIs from `.env`.
  - Encapsulates transaction build/sign/send for peer and aggregator `mint` calls.
  - Exposes getters for Aggregator and Peer queries (round, status, details, etc.).
- ML and hashing utilities:
  - `federated.model_manager`: Keras model, `evaluate_acc`, `average_layerwise` (layer‑wise FedAvg).
  - `federated.utils`: `flatten_weights` (concatenation), `hash_weights` (Keccak‑256), timestamps and timing.
  - `federated.data_handler`: MNIST loading/normalization and client split.

Operational notes:
- Seeds are fixed to improve reproducibility in examples.
- Before mint operations, the connector may warn on low ETH balances to prevent gas errors.
- The connector estimates gas, sets `gasPrice` and `chainId`, signs with provided keys, and waits for receipts.

## End‑to‑End Flow (Single Round)
1. Read `currentRound` on‑chain (defaults to 0 after aggregator deployment).
2. Off‑chain: peers train locally for 1 epoch and compute `weight_hash` + `test_accuracy` per peer.
3. Off‑chain: aggregator performs FedAvg, evaluates globally, measures `duration_sec`, and composes the round JSON.
4. On‑chain (peers): each peer mints their NFT for `roundNumber = prevRound + 1` with its JSON payload (idempotence via `lastParticipatedRound`).
5. On‑chain (aggregator): mints the round NFT, updates `modelWeightHash`, persists `roundDetails`, increments `currentRound`.
6. Off‑chain: verifies the on‑chain state matches local hashes and JSON; logs the outcome.

Ending the federation:
- When appropriate, the aggregator calls `endFederation()` to block further rounds.

## Sequence Diagram (Single Round)
```text
Participants:
  Peer[i] | Training Orchestrator | Web3Connector | FedPeerNFT[i] | FedAggregatorNFT | EVM/Chain

Peer[i]                -> Training Orchestrator : Local training (1 epoch) produces weights_i
Training Orchestrator  -> Training Orchestrator : hash(weights_i)=h_i; evaluate -> acc_i
... repeat for all peers ...
Training Orchestrator  -> Training Orchestrator : FedAvg(weights_1..N) -> avg_weights; evaluate global acc

Training Orchestrator  -> Web3Connector        : peer_get_last_round(i)
Web3Connector          -> FedPeerNFT[i]        : call getLastParticipatedRound()
FedPeerNFT[i]          -> Web3Connector        : lastRound
alt lastRound < targetRound
  Training Orchestrator-> Web3Connector        : mint_peer_round(targetRound, payload_i, i)
  Web3Connector        -> FedPeerNFT[i]        : mint(roundNumber=targetRound, payload=JSON)
  FedPeerNFT[i]        -> EVM/Chain            : persist payload; update lastParticipatedRound; mint NFT(tokenId=targetRound)
  EVM/Chain            -> Web3Connector        : tx receipt
else lastRound >= targetRound
  Training Orchestrator: skip peer mint (idempotence)
end

Training Orchestrator  -> Web3Connector        : mint_aggregator_round(hash_avg, round_info_json)
Web3Connector          -> FedAggregatorNFT     : mint(modelWeightsHash=hash_avg, roundInfo=JSON)
FedAggregatorNFT       -> EVM/Chain            : increment currentRound; persist roundDetails/roundWeights; mint NFT(tokenId=currentRound)
EVM/Chain              -> Web3Connector        : tx receipt

Training Orchestrator  -> Web3Connector        : get_current_round()
Web3Connector          -> FedAggregatorNFT     : call getCurrentRound()
FedAggregatorNFT       -> Web3Connector        : currentRound
Training Orchestrator  -> Web3Connector        : get_round_details(targetRound), get_round_weight/hash(targetRound)
Web3Connector          -> FedAggregatorNFT     : call getters
FedAggregatorNFT       -> Web3Connector        : JSON details, hash
Web3Connector          -> Training Orchestrator: values for local equality checks
```

## Mermaid Diagram (Rendered)
```mermaid
sequenceDiagram
    autonumber
    participant P as Peer (i)
    participant O as Orchestrator
    participant W as Web3Connector
    participant PC as FedPeerNFT
    participant AC as FedAggregatorNFT
    participant CH as EVM Chain

    P->>O: Train 1 epoch -> weights_i
    O->>O: hash(weights_i)=h_i; evaluate acc_i
    O->>O: FedAvg(all weights) -> avg_weights; eval global

    O->>W: peer_get_last_round(i)
    W->>PC: getLastParticipatedRound()
    PC-->>W: lastRound
    alt lastRound < targetRound
        O->>W: mint_peer_round(targetRound, payload_i, i)
        W->>PC: mint(roundNumber, payload)
        PC-->>W: tx receipt
    else Peer already minted
        O-->>O: skip (idempotence)
    end

    O->>W: mint_aggregator_round(hash_avg, round_info)
    W->>AC: mint(weightsHash, roundInfo)
    AC-->>W: tx receipt

    O->>W: get_current_round()
    W->>AC: getCurrentRound()
    AC-->>W: currentRound

    O->>W: get_round_details(targetRound)
    W->>AC: getRoundDetails(round)
    AC-->>W: details JSON

    O->>W: get_round_weight(targetRound)
    W->>AC: getRoundWeight(round) / getRoundHash(round)
    AC-->>W: hash

    W-->>O: verification OK

    Note over AC,PC: Access control enforced (only owner can mint)
```

## Environment and Configuration
`.env` (local Anvil example):
- `WEB3_HTTP_PROVIDER`: HTTP RPC (e.g., `http://127.0.0.1:7545`).
- `AGGREGATOR_PRIVATE_KEY`: aggregator/admin EOA private key.
- `CLIENT_PRIVATE_KEYS`: CSV list of peer EOA private keys.
- `AGGREGATOR_CONTRACT_ADDRESS`: aggregator contract address (post‑deploy).
- `CLIENT_CONTRACT_ADDRESSES`: CSV of peer contract addresses (post‑deploy).
- `AGGREGATOR_ABI_PATH`, `CLIENT_ABI_PATH`: ABI JSON paths for Web3.py.
- Optional: `MIN_TX_ETH_BALANCE` (warn on low balance).

The Makefile can update `.env` after deployments and regenerates ABIs via the `abi` target.

## Tooling and DevOps
- Foundry (forge/cast/anvil): build, test, ABI inspection, deploy/mint via scripts.
- Makefile: one‑command orchestration (start/stop anvil, build/test, deploy aggregator/peers, funding, demo, status, hash verification).
- Foundry scripts:
  - `DeployAggregator.s.sol`: deploy the aggregator contract.
  - `DeployPeer.s.sol`: deploy peer contracts bound to provided EOAs.
  - `MintAggregatorRound.s.sol`, `MintPeerParticipation.s.sol`: explicit mints from CLI.
  - `EndFederation.s.sol`: close the federation process.
- Verification tools:
  - `tools/weights_hash.py`: compute a local hash over weights (.npy/.npz/.h5/.keras) and compare against on‑chain.
  - Make targets `verify-agg-hash` / `verify-peer-hash`: automated comparisons between local and on‑chain values.

## Security, Access Control, and Consistency
- Access control:
  - Aggregator: only `owner()` can call `mint()` and `endFederation()`.
  - Peer: only `owner()` (peer EOA) can call `mint()`; only `aggregatorAddress` can `stopPeer()/restartPeer()`.
- Address consistency: overridden `transferOwnership` keeps `aggregatorAddress`/`peerAddress` synchronized with `owner()` to prevent governance drift.
- Peer idempotence: `roundNumber > lastParticipatedRound` prevents duplicate or retrograde mints.
- Determinism: hashing and compact JSON enable exact string equality between local and on‑chain values.
- Privacy: no raw data or weights on‑chain; only hashes and non‑sensitive metadata.

## Operational Considerations and Limitations
- Gas costs scale with JSON size; keep payloads compact and stable.
- The demos target local networks (Anvil). On public networks, harden key management, gas budgeting, and observability.
- The NFT semantics are functional for audit (1 token/round); they are not designed for secondary‑market transfers.

## Possible Extensions
- Per‑layer proofs (Merkle trees) with IPFS CIDs for off‑chain weights.
- External storage (IPFS/S3) with on‑chain CIDs inside round JSON.
- Peer reputation/slashing and dynamic admission rules.
- CLI analytics for longitudinal round analysis.

## Component Map (Primary References)
- Contracts:
  - `src/smart_contracts/FedAggregator.sol`
  - `src/smart_contracts/FedPeer.sol`
- Python orchestration:
  - `src/federated/training_orchestrator.py`
  - `src/federated/blockchain_connector.py`
  - `src/federated/model_manager.py`, `src/federated/utils.py`, `src/federated/data_handler.py`
- ABI and scripts:
  - `src/abi/Aggregator_ABI.json`, `src/abi/Client_ABI.json`
  - `script/*.s.sol`
- Makefile and tests:
  - `Makefile`
  - `tests/solidity/*`, `tests/python/*`

This architecture separates responsibilities and risk surfaces: on‑chain stores minimal proofs; off‑chain executes ML and verification; tooling ensures repeatability and complete auditability of the federated learning process.
