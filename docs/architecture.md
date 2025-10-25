
# System Architecture – Federated AI Web3 Auditing

This document explains the purpose, components, and trust model for auditable federated training on‑chain. The system stores only Keccak‑256 weight hashes and compact JSON, so auditors can reproduce and validate proofs without exposing raw weights or data. Trust is minimized: correctness relies on deterministic hashing and public on‑chain state.

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

Storage and getters (summary)

| Contract | Key / Getter | Type | Meaning |
| --- | --- | --- | --- |
| Aggregator | modelHash | string | Initial model hash (baseline) |
| Aggregator | modelWeightHash / getModelWeightHash() | string | Latest aggregated weight hash |
| Aggregator | currentRound / getCurrentRound() | uint256 | Current global round (1‑based) |
| Aggregator | federatedStatus | uint8 | 0=in progress, 1=ended |
| Aggregator | aggregatorAddress / getAggregator() | address | Governance/owner address |
| Aggregator | roundWeights[round] / getRoundWeight(round) | string | Aggregated weight hash per round |
| Aggregator | roundDetails[round] / getRoundDetails(round) | string | Compact JSON metadata per round |
| Aggregator | roundHashes[round] / getRoundHash(round) | string | Alias for compatibility |
| Peer | peerAddress / getPeerAddress() | address | Peer owner address |
| Peer | aggregatorAddress / getAggregatorAddress() | address | Linked aggregator address |
| Peer | lastParticipatedRound / getLastParticipatedRound() | uint256 | Last round this peer joined |
| Peer | peerStatus / getPeerStatus() | uint8 | 0=active, 1=inactive |
| Peer | roundDetails[round] | string | Peer JSON payload per round |

Events (summary)

| Contract | Event | When | Fields | Purpose |
| --- | --- | --- | --- | --- |
| Aggregator | AggregatorRoundMinted | On round mint | roundNumber, modelWeightsHash, roundInfo | Anchor aggregated hash and metadata |
| Aggregator | FederationEnded | On federation end | finalRound | Freeze further minting |
| Peer | PeerMinted | On peer mint | roundNumber, payload | Anchor peer payload for that round |
| Peer | PeerStatusChanged | On status change | status | Audit lifecycle (active/inactive) |

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

Primary formats (JSON examples use snake_case):
- Peer payload (for `FedPeerNFT.mint`):
  - `{"peer_id": <int>, "round": <int>, "weight_hash": <hex>, "test_accuracy": <float>}`
- Aggregator round details (for `FedAggregatorNFT.mint`):
  - `{"round_id": <int>, "timestamp": <RFC3339Z>, "duration_sec": <float>, "participants": <int>, "local_epochs": 1, "batch_size": <int>, "avg_round_accuracy": <float>, "lr": <float>}`

Both are produced in compact form (no spaces after commas or colons) to ensure stable comparisons.

### Determinism Details
- Weight dtype and layout: use float32 and C-order (row-major). Hashing uses `flatten_weights(weights).tobytes()` with stable layer order.
- Layer ordering: for Keras, `model.get_weights()` order is deterministic; keep the same architecture across peers.
- NPZ/HDF5 inputs: when verifying against on-chain, ensure consistent key order (provide `KEYS_ORDER` if needed) and dtype.
- JSON serialization: use compact separators (`,`, `:`) and stable key order to allow string-level equality checks.
- Seeding: the orchestrator sets seeds for NumPy, TensorFlow, and Python RNG to improve repeatability in demos.

### JSON Field Definitions
- Peer payload (stored in `FedPeerNFT.roundDetails[round]`):
  - Required fields: `peer_id` (int), `round` (int >= 1), `weight_hash` (hex string), `test_accuracy` (float [0,1]).
  - Example (compact): `{"peer_id":1,"round":3,"weight_hash":"abcd...","test_accuracy":0.9123}`
- Aggregator round info (stored in `FedAggregatorNFT.roundDetails[round]`):
  - Required fields: `round_id` (int >= 1), `timestamp` (RFC3339Z), `duration_sec` (float), `participants` (int), `local_epochs` (int), `batch_size` (int), `avg_round_accuracy` (float), `lr` (float).
  - Example (compact): `{"round_id":3,"timestamp":"2025-01-01T00:00:00Z","duration_sec":1.23,"participants":5,"local_epochs":1,"batch_size":64,"avg_round_accuracy":0.88,"lr":0.001}`

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

Diagram
- For the full sequence (including idempotence and retries), see `docs/diagrams/sequence_full.mmd`.

Naming
- JSON keys use snake_case (e.g., `round_id`, `weight_hash`), while Solidity functions and events use camelCase (e.g., `getCurrentRound`, `modelWeightsHash`). This document preserves both conventions intentionally.


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

### Security Hardening (Public Networks)
- Key management: never commit secrets; use hardware wallets or secure vaults for keys. Prefer multisig for aggregator governance.
- Gas/risk: set appropriate `chainId`, gas price caps, and monitoring; handle retries/backoffs at the orchestrator level.
- Contract upgrades: if governance moves, use `changeAggregator` or `transferOwnership` to keep state consistent.
- NFT semantics: tokens are ERC‑721 and transferable; audit semantics rely on on-chain state (round metadata) rather than current token owner.

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
