import subprocess
import sys
from pathlib import Path

import numpy as np

from federated.utils import hash_weights


def run_script(args):
    cmd = [sys.executable, str(Path("tools") / "weights_hash.py")] + args
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return res.stdout.strip()


def test_weights_hash_npy(tmp_path: Path):
    arr = np.arange(12, dtype=np.float32)
    f = tmp_path / "flat.npy"
    np.save(f, arr)
    out = run_script(["--file", str(f)])
    assert out == hash_weights(arr)


def test_weights_hash_npz_with_order(tmp_path: Path):
    a = np.array([1, 2, 3], dtype=np.float32)
    b = np.array([4, 5], dtype=np.float32)
    f = tmp_path / "weights.npz"
    np.savez(f, b=b, a=a)

    out_default = run_script(["--file", str(f)])
    expected_default = hash_weights(np.concatenate([a.ravel(), b.ravel()]))
    assert out_default == expected_default

    order_file = tmp_path / "order.txt"
    order_file.write_text("b\na\n", encoding="utf-8")
    out_ordered = run_script(["--file", str(f), "--keys-order", str(order_file)])
    expected_ordered = hash_weights(np.concatenate([b.ravel(), a.ravel()]))
    assert out_ordered == expected_ordered

