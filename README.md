# Federated AI Web3 Auditing

Federated AI Web3 Auditing is a research‑driven reference implementation that brings auditability, provenance, and verifiability to Federated Learning (FL) by anchoring training round evidence on a blockchain. Each global round and each peer’s participation is recorded on‑chain as a minimal, immutable artifact: a Keccak‑256 hash of model weights and a compact JSON payload of metrics/metadata, minted as NFTs for traceability.

The project blends three layers:
- Smart contracts (Solidity) that model the Aggregator and Peer audit trail as ERC‑721 NFTs.
- A Python orchestration layer (TensorFlow + Web3.py) that trains, aggregates, hashes, and writes proof artifacts on‑chain.
- A developer workflow (Foundry + Makefile) that automates local chain setup, deployment, interaction, and verification.

## Why and Story
Modern ML systems increasingly operate under federated paradigms where data remains at the edge. While privacy improves, auditability often suffers: How do we prove which peers participated, which weights were used, what accuracy was achieved, and when? This repository emerged from the need to make FL processes tamper‑evident and reproducible for compliance, research validation, and cross‑organization trust.

Design principles that shaped the project:
- Minimal on‑chain footprint: store only what is necessary (hashes + compact JSON), never raw training data or weights.
- Verifiability first: deterministic hashing and round‑by‑round artifacts that can be validated off‑chain at any time.
- Practical developer experience: batteries‑included automation for local chains, deployment, queries, and integrity checks.

## Key Features
- On‑chain audit trail of FL rounds and peer participations via NFTs.
- Deterministic Keccak‑256 hashing of flattened/concatenated weights.
- Python orchestrator that trains clients, performs FedAvg, evaluates, and pushes proofs on‑chain.
- Foundry‑based contracts, scripts, and tests for a fast EVM dev loop.
- Makefile targets for one‑command setup, queries, and verification.
- Integrity verification of local weights vs. on‑chain hashes (aggregator and peer payloads).

## Architecture Overview
- FedAggregatorNFT (Solidity):
  - Public state: `currentRound`, `modelHash`, `modelWeightHash`, `federatedStatus`, `roundDetails`, `roundWeights`.
  - One NFT per global round (tokenId = round number). Minting updates per‑round metadata and emits events.
  - Governance lives at the aggregator address (Ownable).
- FedPeerNFT (Solidity):
  - Public state: `peerAddress`, `lastParticipatedRound`, `peerStatus`, `roundDetails`.
  - One NFT per peer participation per round (tokenId = round number). Payload holds the peer’s JSON (e.g., hash + metrics).
- Python layer:
  - `src/federated/training_orchestrator.py`: local training, FedAvg, evaluation, hashing, on‑chain writes + verification.
  - `src/federated/blockchain_connector.py`: Web3 reads/writes to Aggregator/Peer contracts.
  - `src/federated/model_manager.py`, `src/federated/utils.py`, `src/federated/data_handler.py`: model, hashing, data utils.

For a deeper dive, see: `docs/architecture.md`, `docs/fl_overview.md`, `docs/web3_auditing.md`.

## Repository Layout
- `src/smart_contracts/` — Solidity contracts (Aggregator and Peer)
- `script/` — Foundry scripts (deploy/mint/end)
- `test/` — Foundry tests (Solidity)
- `src/` — Python package (federated training + Web3 connector)
- `tests/` — Python tests (pytest)
- `tools/` — Python CLI utilities (hashing, payload parsing)
- `src/abi/` — Generated ABI JSON files
- `broadcast/`, `out/`, `cache/` — Foundry artifacts and run traces
- `logs/` — Local node and deploy logs

## Quickstart

Prerequisites
- Python 3.10+
- Foundry (forge, cast, anvil)

Install Python deps
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Ensure Foundry is installed and in PATH:
```bash
forge --version && cast --version && anvil --version
```

Create `.env` (example for local Anvil):
```env
WEB3_HTTP_PROVIDER=http://127.0.0.1:7545

# Aggregator/admin EOA private key (hex)
AGGREGATOR_PRIVATE_KEY=0x...

# Comma‑separated list of peer private keys (EOAs)
CLIENT_PRIVATE_KEYS=0x...,0x...

# Populated by Make targets after deployment
AGGREGATOR_CONTRACT_ADDRESS=
CLIENT_CONTRACT_ADDRESSES=

# ABI file paths used by the Python connector
AGGREGATOR_ABI_PATH=src/abi/Aggregator_ABI.json
CLIENT_ABI_PATH=src/abi/Client_ABI.json
```

Boot, deploy, and demo
```bash
# One‑shot reset: start Anvil, build, deploy, fund, and regenerate ABIs
make reset

# Run the federated training demo (default 1 round)
make demo ROUNDS=1

# Show environment and contracts status
make status
```

All Make targets are documented in `docs/target.md` (usage, variables, and examples).

## Verification Workflows
This project makes it easy to verify that local weights correspond to the hashes recorded on‑chain.

Supported weight files
- `.npy`: a single array (vector or tensor; it will be flattened).
- `.npz`: multiple arrays; default alphabetical key order or provide an order file (one key per line).
- `.h5` / `.keras`: a full Keras model; weights are taken via `model.get_weights()` and concatenated in order.

Commands
```bash
# Verify local weights against the Aggregator’s round hash
make verify-agg-hash ROUND_NUMBER=3 WEIGHTS=weights_round3.npz [KEYS_ORDER=order.txt] [AGG_ADDR=0x...]

# Verify local weights against a Peer’s payload (weight_hash) at a given round
make verify-peer-hash PEER_INDEX=0 ROUND_NUMBER=2 WEIGHTS=model_r2.h5 [KEYS_ORDER=order.txt]
```

Under the hood, these use `tools/weights_hash.py` to compute Keccak‑256 over the flattened/concatenated weights and compare it to the on‑chain value.

## Development and Testing

Solidity
- Contracts live in `src/smart_contracts`.
- Foundry tests: `make test` or `make test-sol`

Python
- Core logic lives under `src/federated`.
- Python tests live in `tests/`. Run them via:
  ```bash
  make test-py
  # or
  PYTHONPATH=src python -m pytest -q
  ```

## Operational Notes and Constraints
- Never store raw training data or full weights on‑chain; only hashes and compact metadata are recorded.
- Gas costs scale with metadata size; keep round payloads compact and deterministic.
- Determinism: training seeds are fixed in the orchestrator to improve reproducibility of examples.
- The repository targets local development (Anvil). For public networks, harden key management and deployment procedures.

## Roadmap (Indicative)
- Optional Merkle schemes for per‑layer hash proofs.
- Off‑chain storage bindings (IPFS/S3) with on‑chain CIDs.
- Extended peer reputation and slashing hooks.
- CLI utilities for richer round/peer analytics.

## License
This project is licensed under the MIT License. See `LICENSE` for details.

## Acknowledgments
- OpenZeppelin (ERC‑721, Ownable)
- Foundry (forge, cast, anvil)
- TensorFlow / Keras
- Web3.py and Ethereum tooling ecosystem
