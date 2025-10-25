# Federated AI Web3 Auditing

[![CI](https://github.com/riccardo-csl/FederatedAI_Web3_Audit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/riccardo-csl/FederatedAI_Web3_Audit/actions/workflows/ci.yml)
[![ABI Artifacts](https://github.com/riccardo-csl/FederatedAI_Web3_Audit/actions/workflows/abi-artifacts.yml/badge.svg?branch=main)](https://github.com/riccardo-csl/FederatedAI_Web3_Audit/actions/workflows/abi-artifacts.yml)
[![Deploy (Testnet)](https://github.com/riccardo-csl/FederatedAI_Web3_Audit/actions/workflows/deploy-testnet.yml/badge.svg?branch=main)](https://github.com/riccardo-csl/FederatedAI_Web3_Audit/actions/workflows/deploy-testnet.yml)

An auditable federated‑training reference that records on‑chain proofs for every round and peer participation. It stores only Keccak‑256 weight hashes and compact JSON metadata, never raw weights or data.

How it works: the Python layer trains and aggregates, computes Keccak‑256 over flattened weights, and mints two NFTs per round (aggregator round and each peer’s participation). It then re‑reads on‑chain state to assert integrity.

Quick tour
- Architecture overview: `docs/architecture.md`
- Make targets and recipes: `docs/targets.md`
- Verification and diagnosis: `docs/verification.md`

Diagram (overview)
- See `docs/diagrams/sequence_overview.mmd` for a compact end‑to‑end sequence.

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

All Make targets are documented in `docs/targets.md` (usage, variables, and examples). See also `docs/verification.md` for audit flows.

Try it quickly
```bash
# Start local chain, build, deploy aggregator/peers, fund accounts
make reset

# Run a 1‑round demo and write proofs on‑chain
make demo ROUNDS=1

# Show node, contracts, and round status
make status

# Verify an aggregator round hash against local weights
make verify-agg-hash ROUND_NUMBER=1 WEIGHTS=weights_round1.npz [KEYS_ORDER=order.txt]

# Verify a peer payload (weight_hash) against local weights
make verify-peer-hash PEER_INDEX=0 ROUND_NUMBER=1 WEIGHTS=model_r1.h5
```
See `docs/targets.md` for options and variations.

## Troubleshooting (Quick)
- RPC unreachable: ensure Anvil is running and `RPC_URL`/`WEB3_HTTP_PROVIDER` match (`make anvil-start`, then `make status`).
- Insufficient funds: top up EOA balances on Anvil (`make fund-accounts`) or use a testnet faucet.
- JSON quoting in shell: wrap JSON in single quotes, e.g. `ROUND_INFO='{"round_id":1,...}'`.
- ABI mismatch: regenerate with `make abi` after changing contracts.
- Hash mismatch: confirm dtype/ordering. Use `tools/weights_hash.py` and ensure float32, C-order, deterministic layer ordering.
- Foundry not in PATH: install Foundry or set `FOUNDRY` path; verify with `forge --version`.

## Troubleshooting (top 3)
- RPC connectivity: ensure Anvil is running and `RPC_URL`/`WEB3_HTTP_PROVIDER` match. See `docs/targets.md` → status.
- Funding: top up EOA balances (`make fund-accounts` on Anvil, faucet on testnet). See `docs/targets.md`.
- ABI mismatch: regenerate ABIs after contract changes (`make abi`). See `docs/verification.md` for audit checks.

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

## Docs map
- `docs/architecture.md` — full architecture, storage and events
- `docs/targets.md` — common recipes + full reference
- `docs/verification.md` — verification golden path + decision tree
- `docs/diagrams/sequence_full.mmd` — detailed sequence (idempotence, retries, receipts)

## CI/CD
This repository ships with GitHub Actions for tests, artifacts, and manual deploys.
- CI: Solidity and Python tests on every push/PR — see the CI badge above.
- ABI artifacts: generates ABI JSONs on `main` and uploads them as artifacts.
- Testnet deploy: manual workflow; configure `WEB3_HTTP_PROVIDER`, `AGGREGATOR_PRIVATE_KEY`, `CLIENT_PRIVATE_KEYS` in repo Secrets.

## License
This project is licensed under the MIT License. See `LICENSE` for details.

## Acknowledgments
- OpenZeppelin (ERC‑721, Ownable)
- Foundry (forge, cast, anvil)
- TensorFlow / Keras
- Web3.py and Ethereum tooling ecosystem
