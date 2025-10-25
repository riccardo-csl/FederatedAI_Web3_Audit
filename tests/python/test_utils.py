import re
import numpy as np
from Crypto.Hash import keccak

from federated.utils import utc_timestamp, flatten_weights, hash_weights


def test_utc_timestamp_format():
    ts = utc_timestamp()
    assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", ts)


def test_flatten_weights_concatenation():
    w1 = np.array([[1, 2], [3, 4]], dtype=np.float32)
    w2 = np.array([5, 6], dtype=np.float32)
    flat = flatten_weights([w1, w2])
    assert flat.dtype == np.float32
    assert flat.shape == (6,)
    np.testing.assert_allclose(flat, np.array([1, 2, 3, 4, 5, 6], dtype=np.float32))


def test_hash_weights_matches_manual_keccak():
    arr = np.arange(10, dtype=np.float32)
    h_lib = hash_weights(arr)

    k = keccak.new(digest_bits=256)
    k.update(arr.tobytes())
    h_manual = k.hexdigest()
    assert h_lib == h_manual

