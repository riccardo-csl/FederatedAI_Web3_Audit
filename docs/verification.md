# Verification Guide – Audit and Integrity Checks

Verification in 60 seconds
- Aggregator vs local: `make verify-agg-hash ROUND_NUMBER=1 WEIGHTS=weights_round1.npz [KEYS_ORDER=order.txt]`
- Peer vs local: `make verify-peer-hash PEER_INDEX=0 ROUND_NUMBER=1 WEIGHTS=model_r1.h5`

This guide explains how to audit and verify that local model weights and metadata match what is recorded on‑chain for both aggregator rounds and peer participations. It also details supported weight formats, NPZ key ordering, common mismatch scenarios, and concrete diagnosis steps.

## Scope and Goals
- Verify Aggregator round integrity: local aggregated weight hash and JSON details match on‑chain values.
- Verify Peer participation integrity: local peer weight hash matches the `weight_hash` recorded in the peer payload for a given round.
- Provide deterministic hashing recipes and handling for `.npy`, `.npz`, `.h5`, `.keras` formats.

## On‑Chain Audit Artifacts
- Aggregator (contract `FedAggregatorNFT`):
  - `roundWeights[round]` (or `roundHashes[round]`): Keccak‑256 hash of aggregated weights.
  - `roundDetails[round]`: compact JSON with round metadata (timestamp, duration, participants, metrics, etc.).
- Peer (contract `FedPeerNFT`):
  - `roundDetails[round]`: peer JSON payload containing `weight_hash` and metrics for that round.

## Deterministic Hashing Recipe
To avoid false mismatches, follow these rules when computing local hashes:
- Data type and layout: use float32 arrays and C‑order (row‑major). Flatten by simple `.flatten()` or `.ravel(order="C")`.
- Concatenation order: respect layer order as produced by your framework. In Keras, `model.get_weights()` yields a deterministic order.
- Digest function: Keccak‑256 (Ethereum) over the raw bytes: `keccak256(flattened.tobytes())`.
- Hex format: lower‑case hex string is standard; treat comparison case‑insensitively if needed.

The helper used in this repo is `tools/weights_hash.py` and the Python function `federated.utils.hash_weights()`.

## Supported Weight Formats
- `.npy` (single array)
  - Represents one tensor/array. It is flattened to 1D then hashed.
  - Ensure dtype is float32 for consistency.
  - Example:
    ```bash
    python tools/weights_hash.py --file path/to/weights.npy
    ```

- `.npz` (multiple arrays)
  - Container of multiple arrays keyed by name. By default, arrays are concatenated using alphabetical key order.
  - If your expected order differs, provide `--keys-order <file>` where the file lists one key per line in the exact concatenation order.
  - Ensure all arrays are float32 or explicitly cast before hashing.
  - Example (default alphabetical order):
    ```bash
    python tools/weights_hash.py --file path/to/weights_round3.npz
    ```
  - Example (explicit key order):
    ```bash
    # order.txt
    dense/kernel:0
    dense/bias:0
    dense_1/kernel:0
    dense_1/bias:0

    python tools/weights_hash.py --file path/to/weights_round3.npz --keys-order order.txt
    ```

- `.h5` / `.keras` (Keras model files)
  - Load with TensorFlow/Keras, call `model.get_weights()` and follow the natural layer order for concatenation and hashing.
  - Optimizer state is not part of `get_weights()`; hashes should remain stable across the same architecture.
  - Example:
    ```bash
    python tools/weights_hash.py --file path/to/model_r2.h5
    ```

## Verification Flows

### Aggregator Round Verification
Goal: local aggregated weights hash and JSON must match the on‑chain values for a target round.

1) Retrieve on‑chain hash and details
- On‑chain hash: prefer `getRoundWeight(round)`, falling back to `getRoundHash(round)` if needed.
- On‑chain details: `getRoundDetails(round)` returns the exact JSON string stored.

2) Compute local hash
- Use the same weight file you intend to audit (`.npy/.npz/.h5/.keras`).
- Ensure deterministic ordering and float32 dtype.

3) Compare
- Hash: string equality (case‑insensitive recommended for hex).
- JSON details: string equality (must be byte‑for‑byte equal—no extra spaces or key reordering).

4) Commands (Make targets)
```bash
# Compare local hash against Aggregator on‑chain hash for a round
make verify-agg-hash ROUND_NUMBER=3 WEIGHTS=weights_round3.npz [KEYS_ORDER=order.txt] [AGG_ADDR=0x...]
```

### Peer Participation Verification
Goal: local peer weight hash matches the `weight_hash` field inside the peer’s JSON payload for a round.

1) Retrieve on‑chain peer payload
- From `FedPeerNFT.roundDetails(round)` via RPC or helper scripts.
- Parse the JSON and extract `weight_hash`.

2) Compute local hash
- Same deterministic hashing as above.

3) Compare
- Hash: string equality (case‑insensitive for hex).

4) Commands (Make targets)
```bash
# Compare local hash against a Peer’s on‑chain weight_hash for a round
make verify-peer-hash PEER_INDEX=0 ROUND_NUMBER=2 WEIGHTS=model_r2.h5 [KEYS_ORDER=order.txt]

# Or address-based
make verify-peer-hash PEER_ADDR=0x... ROUND_NUMBER=2 WEIGHTS=model_r2.h5
```

## Decision Tree for Mismatches (compact)
- Dtype not float32? Cast arrays to float32 and retry.
- File ordering/flattening: ensure C‑order flatten; for `.npz`, align key order (use `--keys-order`).
- Layer order: confirm `model.get_weights()` order and architecture are identical.
- JSON minification: aggregator `roundDetails` must be compact (no spaces) and stable key order.
- Chain/network mismatch: double‑check you’re reading the intended network/contract address.
- Nonce/gas issues (writes): ensure prior txs were mined; re‑read state or retry with backoff.

**Naming note:** JSON uses `weight_hash` while the aggregator event/field uses `modelWeightsHash`. Compare values as strings; do not rename on‑chain fields.

## Practical Mismatch Scenarios and Diagnosis

1) Dtype mismatch (float64 vs float32)
- Symptom: different hashes despite identical numeric values.
- Fix: cast arrays to float32 (e.g., `arr.astype(np.float32)`) before hashing.

2) NPZ key order mismatch
- Symptom: `.npz` hash mismatches only; `.h5`/.keras may match.
- Cause: concatenation order differs from default alphabetical order.
- Fix: supply `--keys-order` to `tools/weights_hash.py` with the exact expected order.

3) Flatten/layout mismatch (Fortran vs C order)
- Symptom: mismatch even with same dtype/values.
- Fix: ensure flattening in C‑order (row‑major). In NumPy: `arr.ravel(order="C")`.

4) Layer ordering differences
- Symptom: mismatch when models were saved/reconstructed differently.
- Fix: verify that `model.get_weights()` orders layers identically (same architecture and layer names), or align arrays explicitly.

5) JSON formatting differences
- Symptom: Aggregator `roundDetails` mismatch even though fields appear equal.
- Fix: ensure compact JSON with stable key order and consistent float formatting. Compare raw strings (no whitespace).

6) Non‑determinism in training
- Symptom: peer hashes differ across runs.
- Fix: set seeds (NumPy/TensorFlow/Python), keep deterministic ops, and avoid stochastic layers or different batch orders if consistency is required for audit.

7) Case sensitivity
- Symptom: same hex with different case appears “different”.
- Fix: compare hashes in lower‑case.

## Low‑Level Diagnosis Aids

Compute hash manually in Python for a single array
```python
import numpy as np
from Crypto.Hash import keccak

arr = np.load('weights.npy').astype(np.float32)
flat = arr.ravel(order='C')
k = keccak.new(digest_bits=256)
k.update(flat.tobytes())
print(k.hexdigest())
```

Inspect `.npz` contents and order
```python
import numpy as np
npz = np.load('weights_round3.npz')
print('keys:', list(npz.keys()))
for k in sorted(npz.keys()):
    print(k, npz[k].dtype, npz[k].shape)
```

Verify on‑chain values via Make or cast
```bash
# Aggregator hash
make verify-agg-hash ROUND_NUMBER=3 WEIGHTS=weights_round3.npz

# Peer hash
make verify-peer-hash PEER_INDEX=0 ROUND_NUMBER=2 WEIGHTS=model_r2.h5
```

## Security and Privacy Notes
- Never upload local weights on‑chain; only the hash and compact metadata are stored.
- Keep private keys out of the repository; `.env` is ignored by `.gitignore` and should not be committed.
- On public networks, consider multisig governance for the Aggregator and monitor events for audit.

## Summary Checklist
- [ ] Use float32 and C‑order flattening.
- [ ] Ensure deterministic layer ordering (e.g., Keras `get_weights()`).
- [ ] For `.npz`, provide `--keys-order` if alphabetical order is not correct.
- [ ] Use compact JSON (no extra spaces) with stable key order.
- [ ] Compare hex hashes case‑insensitively.
- [ ] Use `make verify-agg-hash` / `make verify-peer-hash` for quick checks.
