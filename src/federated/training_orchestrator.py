# src/federated/training_orchestrator.py
import json, random, os
import numpy as np
from .data_handler import load_mnist_normalized, split_among_clients
from .model_manager import build_client_model, evaluate_acc, average_layerwise
from .utils import utc_timestamp, wall_time, hash_weights, flatten_weights
from .blockchain_connector import Web3Connector
import tensorflow as tf

def _safe_try(callable_fn, *args, default=None):
    try:
        return callable_fn(*args)
    except Exception:
        return default

def _peer_info_json(peer_id: int, round_id: int, weight_hash: str, acc: float) -> str:
    # Compact JSON, easy to audit/parse off-chain
    return json.dumps({
        "peer_id": peer_id,
        "round": round_id,
        "weight_hash": weight_hash,
        "test_accuracy": float(acc)
    }, separators=(",", ":"))

def _round_info_json(round_id: int, participants: int, batch_size: int,duration_sec: float, avg_round_accuracy: float, lr: float) -> str:
    return json.dumps({
        "round_id": round_id,
        "timestamp": utc_timestamp(),
        "duration_sec": float(duration_sec),
        "participants": participants,
        "local_epochs": 1,
        "batch_size": batch_size,
        "avg_round_accuracy": float(avg_round_accuracy),
        "lr": float(lr)
    }, separators=(",", ":"))

def _set_seeds(seed: int = 42):
    np.random.seed(seed)
    tf.random.set_seed(seed)
    random.seed(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)

def run_federated(rounds: int = 1, num_clients: int = 5, batch_size: int = 64, lr: float = 0.001):
    _set_seeds(42)

    (xtr, ytr), (xte, yte) = load_mnist_normalized()
    xtr_s, ytr_s = split_among_clients(xtr, ytr, num_clients)
    xte_s, yte_s = split_among_clients(xte, yte, num_clients)

    models = [build_client_model() for _ in range(num_clients)]
    w3c = Web3Connector()

    # Warn on low balances to avoid "insufficient funds for gas * price + value"
    try:
        min_eth = float(os.getenv("MIN_TX_ETH_BALANCE", "0.05"))
        agg_bal = w3c.get_balance_eth(w3c.get_aggregator_account_address())
        if agg_bal < min_eth:
            print(f"[WARN] Aggregator balance low: {agg_bal:.4f} ETH (< {min_eth} ETH)")
        for idx in range(min(num_clients, w3c.peer_count())):
            bal = w3c.get_balance_eth(w3c.get_peer_account_address(idx))
            if bal < min_eth:
                print(f"[WARN] Peer {idx+1} balance low: {bal:.4f} ETH (< {min_eth} ETH)")
    except Exception:
        # Don't block the run if the chain isn't reachable at this stage
        pass

    test_losses, test_accs = [], []

    for _ in range(rounds):
        # 1) Determine target on-chain round: currentRound + 1
        prev_round = _safe_try(w3c.get_current_round, default=0) or 0
        target_round = prev_round + 1

        # 2) Train locally 1 epoch per peer
        t0 = wall_time()
        for m, xt, yt in zip(models, xtr_s, ytr_s):
            m.fit(xt, yt, epochs=1, batch_size=batch_size, validation_split=0.1, verbose=0)

        # 3) Compute hash and accuracy for each peer
        peer_infos = []
        peer_accs = []
        weight_lists = []
        for i, (m, xt_i, yt_i) in enumerate(zip(models, xte_s, yte_s), start=1):
            acc_i = evaluate_acc(m, xt_i, yt_i)
            peer_accs.append(acc_i)
            wi = m.get_weights()
            weight_lists.append(wi)
            h_i = hash_weights(flatten_weights(wi))
            peer_infos.append(_peer_info_json(i, target_round, h_i, acc_i))

        # 4) FedAvg + global evaluation
        avg_w = average_layerwise(weight_lists)
        for m in models:
            m.set_weights(avg_w)
        loss_glob, acc_glob = models[0].evaluate(xte, yte, verbose=0)
        test_losses.append(loss_glob); test_accs.append(acc_glob)

        # 5) Peer mints (roundNumber = target_round) with idempotence
        for peer_idx, info in enumerate(peer_infos):
            # avoid duplicate mints if a previous attempt succeeded
            last_r = _safe_try(w3c.peer_get_last_round, peer_idx, default=0) or 0
            if last_r >= target_round:
                # already minted this round (or beyond) for this peer -> skip
                continue
            w3c.mint_peer_round(target_round, info, peer_idx)
            # optional: verify stored details
            _ = _safe_try(w3c.peer_get_round_details, peer_idx, target_round, default=None)

        # 6) Aggregator mint with round info
        duration = wall_time() - t0
        round_info = _round_info_json(
            round_id=target_round,
            participants=num_clients,
            batch_size=batch_size,
            duration_sec=duration,
            # average of per-peer accuracies computed on test set
            avg_round_accuracy=float(np.mean(peer_accs)),
            lr=lr
        )
        h_avg = hash_weights(flatten_weights(avg_w))
        w3c.mint_aggregator_round(h_avg, round_info)

        # 7) On-chain verification (aggregator)
        cur = _safe_try(w3c.get_current_round, default=0) or 0
        assert cur == target_round, f"currentRound on-chain ({cur}) != target_round ({target_round})"

        on_details = _safe_try(w3c.get_round_details, target_round, default=None)
        if on_details is not None:
            # They must match at the JSON string level
            assert on_details == round_info, "roundDetails on-chain != local roundInfo"

        # roundWeight / roundHash are optional (depends on the contract)
        on_w = _safe_try(w3c.get_round_weight, target_round, default=None)
        on_h = _safe_try(w3c.get_round_hash, target_round, default=None)
        if on_w is not None:
            assert on_w == h_avg, "roundWeight on-chain != aggregated hash"
        elif on_h is not None:
            assert on_h == h_avg, "roundHash on-chain != aggregated hash"

        # print progress
        print(f"[Round {target_round}] acc_glob={acc_glob:.4f} | wrote on-chain ✓")

    return test_losses, test_accs
