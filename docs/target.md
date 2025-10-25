# Makefile Targets – Usage Guide

This document describes how to use every Makefile target in this repo, with required variables and examples. By default, Make runs in quiet mode; add `V=1` for verbose output.

- Quiet: `make <target>`
- Verbose: `make V=1 <target>`
- Default config variables: `ENV_FILE=.env`, `HOST=127.0.0.1`, `PORT=7545`, `RPC_URL=http://127.0.0.1:7545`

Note: Many targets expect keys/addresses in `$(ENV_FILE)`.

## anvil-start
- Purpose: Start an Anvil node in background and wait until the RPC responds.
- Usage: `make anvil-start`
- Side effects: Writes logs to `logs/anvil.log` and the process id to `.anvil.pid`.

## anvil-stop
- Purpose: Stop Anvil using the pid stored in `.anvil.pid`.
- Usage: `make anvil-stop`

## build
- Purpose: Compile smart contracts with Foundry.
- Usage: `make build`

## test
- Purpose: Run Foundry tests.
- Usage: `make test`

## test-sol
- Purpose: Run Solidity tests (Foundry) explicitly.
- Usage: `make test-sol`

## test-py
- Purpose: Run Python tests (pytest) against the code under `src/`.
- Usage: `make test-py`
- Notes: Uses `.venv/bin/python` if present, otherwise `python3`. Sets `PYTHONPATH=src`.

## abi
- Purpose: Regenerate ABI JSON files for Aggregator and Peer contracts.
- Usage: `make abi`
- Output: `src/abi/Aggregator_ABI.json`, `src/abi/Client_ABI.json`

## deploy-agg
- Purpose: Deploy the Aggregator contract and update `.env`.
- Usage: `make deploy-agg MODEL_HASH=<initial_model_hash>`
- Requires in `$(ENV_FILE)`: `AGGREGATOR_PRIVATE_KEY=<hex>`
- Effect: Updates/sets `AGGREGATOR_CONTRACT_ADDRESS` in `$(ENV_FILE)` (backup created).

## fund-accounts
- Purpose: Fund the Aggregator EOA and all peer EOAs on Anvil.
- Usage: `make fund-accounts`
- Requires in `$(ENV_FILE)`: `AGGREGATOR_PRIVATE_KEY=<hex>`, `CLIENT_PRIVATE_KEYS=<pk1,pk2,...>`

## deploy-peers
- Purpose: Deploy one Peer contract per private key and update `.env`.
- Usage: `make deploy-peers`
- Requires in `$(ENV_FILE)`: `AGGREGATOR_PRIVATE_KEY`, `AGGREGATOR_CONTRACT_ADDRESS`, `CLIENT_PRIVATE_KEYS`
- Effect: Writes `CLIENT_CONTRACT_ADDRESSES=<addr1,addr2,...>` in `$(ENV_FILE)` (backup created).

## mint-round
- Purpose: Mint an Aggregator round (write global round details on-chain).
- Usage: `make mint-round MODEL_WEIGHTS_HASH=<keccak256> ROUND_INFO='<json_string>'`
- Requires in `$(ENV_FILE)`: `AGGREGATOR_PRIVATE_KEY`, `AGGREGATOR_CONTRACT_ADDRESS`
- Tip: Use single quotes around the JSON string to avoid shell escaping issues.

## end
- Purpose: End the federation (prevents further Aggregator mints).
- Usage: `make end`
- Requires in `$(ENV_FILE)`: `AGGREGATOR_PRIVATE_KEY`, `AGGREGATOR_CONTRACT_ADDRESS`

## demo
- Purpose: Run the Python federated-training demo which also interacts with the chain.
- Usage: `make demo [ROUNDS=<n>]`

## reset
- Purpose: Full reset of the local environment (stop/start Anvil, rebuild, fund, redeploy).
- Usage: `make reset [MODEL_HASH=<initial_model_hash>]`
- Actions: Stops Anvil, cleans artifacts, starts Anvil, runs `build`, `abi`, `fund-accounts`, `deploy-agg`, `deploy-peers`.

## status
- Purpose: Show status of Anvil, RPC connectivity, Aggregator and Peer contracts.
- Usage: `make status`
- Output: Prints RPC status, Aggregator info (round, status, owner, hashes), and Peer list (status, last round, owner).

## peer-round
- Purpose: Fetch the training payload (JSON) saved by a specific Peer at a given round.
- Usage options:
  - By index (0-based from `CLIENT_CONTRACT_ADDRESSES` in `.env`):
    - `make peer-round PEER_INDEX=<i> ROUND_NUMBER=<n>`
  - By contract address:
    - `make peer-round PEER_ADDR=0x... ROUND_NUMBER=<n>`
- Output: Prints `peer=<address> round=<n>` and the JSON payload.

## peer-rounds
- Purpose: List the training payloads for a Peer across a round range.
- Usage options:
  - `make peer-rounds PEER_INDEX=<i> [FROM=<a>] [TO=<b>]`
  - `make peer-rounds PEER_ADDR=0x... [FROM=<a>] [TO=<b>]`
- Defaults: `FROM=1`, `TO=lastParticipatedRound`
- Output: One line per round with `round=<n> <payload|<empty>>`.

## agg-round
- Purpose: Fetch Aggregator global details for a specific round.
- Usage: `make agg-round ROUND_NUMBER=<n> [AGG_ADDR=0x...]`
- Default for `AGG_ADDR`: taken from `AGGREGATOR_CONTRACT_ADDRESS` in `$(ENV_FILE)`
- Output: Prints `weight_hash=<...>` and `details=<json>`.

## agg-rounds
- Purpose: List Aggregator details across a round range.
- Usage: `make agg-rounds [FROM=<a>] [TO=<b>] [AGG_ADDR=0x...]`
- Defaults: `FROM=1`, `TO=currentRound`
- Output: One line per round with `round=<n> weight_hash=<...> details=<json>`.

## verify-agg-hash
- Purpose: Verify that the local weights hash matches the on-chain Aggregator hash for a round.
- Usage: `make verify-agg-hash ROUND_NUMBER=<n> WEIGHTS=<path> [KEYS_ORDER=<path>] [AGG_ADDR=0x...]`
- Supported `WEIGHTS` formats:
  - `.npy`: a single array (will be flattened).
  - `.npz`: multiple arrays; default alphabetical key order or provide `KEYS_ORDER` (one key per line).
  - `.h5` / `.keras`: a full Keras model file; uses `model.get_weights()` order.
- Output: Prints on-chain and local hashes and `MATCH`/`MISMATCH` (non-zero exit on mismatch).

## verify-peer-hash
- Purpose: Verify that the local weights hash matches the `weight_hash` field in a Peer payload at a given round.
- Usage options:
  - `make verify-peer-hash PEER_INDEX=<i> ROUND_NUMBER=<n> WEIGHTS=<path> [KEYS_ORDER=<path>]`
  - `make verify-peer-hash PEER_ADDR=0x... ROUND_NUMBER=<n> WEIGHTS=<path> [KEYS_ORDER=<path>]`
- Output: Prints on-chain and local hashes and `MATCH`/`MISMATCH` (non-zero exit on mismatch).

## clean-logs
- Purpose: Remove the `logs/` directory (e.g., Anvil and deploy logs).
- Usage: `make clean-logs`

## clean-artifacts
- Purpose: Remove Foundry build artifacts and broadcast traces.
- Usage: `make clean-artifacts`
