import json
import numpy as np
import federated.training_orchestrator as to


def test_peer_info_json_compact_and_fields():
    out = to._peer_info_json(peer_id=2, round_id=5, weight_hash="abcd", acc=0.987)
    assert ", " not in out and ": " not in out
    obj = json.loads(out)
    assert obj == {
        "peer_id": 2,
        "round": 5,
        "weight_hash": "abcd",
        "test_accuracy": 0.987,
    }


def test_round_info_json_deterministic_structure(monkeypatch):
    monkeypatch.setattr(to, "utc_timestamp", lambda: "2022-05-10T12:34:56Z")
    out = to._round_info_json(
        round_id=7,
        participants=3,
        batch_size=64,
        duration_sec=1.234,
        avg_round_accuracy=0.8765,
        lr=0.001,
    )
    assert ", " not in out and ": " not in out
    obj = json.loads(out)
    assert obj["round_id"] == 7
    assert obj["timestamp"] == "2022-05-10T12:34:56Z"
    assert obj["participants"] == 3
    assert obj["local_epochs"] == 1
    assert obj["batch_size"] == 64
    assert obj["duration_sec"] == 1.234
    assert obj["avg_round_accuracy"] == 0.8765
    assert obj["lr"] == 0.001

