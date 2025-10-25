import argparse
import os
import sys
from typing import List

import numpy as np
from Crypto.Hash import keccak


def _keccak256_hex(data: bytes) -> str:
    k = keccak.new(digest_bits=256)
    k.update(data)
    return k.hexdigest()


def _flatten_and_concat(weights: List[np.ndarray]) -> np.ndarray:
    return np.concatenate([w.ravel() for w in weights]) if weights else np.array([], dtype=np.float32)


def _hash_from_npy(path: str) -> str:
    arr = np.load(path, allow_pickle=False)
    if isinstance(arr, np.ndarray):
        flat = arr.ravel()
        return _keccak256_hex(flat.tobytes())
    raise ValueError("Unsupported .npy content")


def _hash_from_npz(path: str, keys_order_file: str | None) -> str:
    with np.load(path, allow_pickle=False) as data:
        keys = list(data.keys())
        if keys_order_file:
            with open(keys_order_file, 'r', encoding='utf-8') as f:
                desired = [ln.strip() for ln in f if ln.strip()]
            # filter to existing keys, in given order
            ordered = [k for k in desired if k in keys]
            # include any remaining keys deterministically at the end
            remaining = sorted([k for k in keys if k not in ordered])
            keys = ordered + remaining
        else:
            keys.sort()
        arrays = [data[k] for k in keys]
        flat = _flatten_and_concat(arrays)
        return _keccak256_hex(flat.tobytes())


def _hash_from_keras(path: str) -> str:
    try:
        # Prefer TensorFlow Keras
        from tensorflow import keras as tf_keras  # type: ignore
        model = tf_keras.models.load_model(path, compile=False)
    except Exception:
        # Fallback to standalone Keras (if available)
        try:
            import keras  # type: ignore
            model = keras.saving.load_model(path)
        except Exception as e2:
            raise RuntimeError(
                "Unable to load model file. Ensure TensorFlow/Keras is installed "
                "and the file is a full model (.h5/.keras), not weights-only."
            ) from e2
    weights = model.get_weights()
    flat = _flatten_and_concat(weights)
    return _keccak256_hex(flat.tobytes())


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(description="Compute keccak256 hash of model weights")
    p.add_argument("--file", required=True, help="Path to weights: .npy (flat), .npz (arrays), .h5/.keras (model)")
    p.add_argument("--keys-order", dest="keys_order", default=None, help="Optional file listing .npz keys order (one per line)")
    args = p.parse_args(argv)

    path = args.file
    if not os.path.isfile(path):
        print(f"File not found: {path}", file=sys.stderr)
        return 2

    ext = os.path.splitext(path)[1].lower()
    try:
        if ext == ".npy":
            h = _hash_from_npy(path)
        elif ext == ".npz":
            h = _hash_from_npz(path, args.keys_order)
        elif ext in (".h5", ".keras"):
            h = _hash_from_keras(path)
        else:
            print(f"Unsupported file extension: {ext}", file=sys.stderr)
            return 2
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    print(h)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

