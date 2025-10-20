from Crypto.Hash import keccak
import numpy as np
from time import time, gmtime, strftime

def utc_timestamp() -> str:
    return strftime("%Y-%m-%dT%H:%M:%SZ", gmtime())

def wall_time() -> float:
    return time()

def hash_weights(flattened: np.ndarray) -> str:
    k = keccak.new(digest_bits=256)
    k.update(flattened.tobytes())
    return k.hexdigest()

def flatten_weights(weights: list[np.ndarray]) -> np.ndarray:
    return np.concatenate([w.flatten() for w in weights])
