import json
import numpy as np
from .data_handler import load_mnist_normalized, split_among_clients
from .model_manager import build_client_model, evaluate_acc, average_layerwise
from .utils import utc_timestamp, wall_time, hash_weights, flatten_weights
from .blockchain_connector import Web3Connector

def run_federated(rounds: int = 1, num_clients: int = 5, batch_size: int = 64):
    (xtr, ytr), (xte, yte) = load_mnist_normalized()
    xtr_s, ytr_s = split_among_clients(xtr, ytr, num_clients)
    xte_s, yte_s = split_among_clients(xte, yte, num_clients)

    models = [build_client_model() for _ in range(num_clients)]
    w3c = Web3Connector()

    test_losses, test_accs = [], []

    for r in range(1, rounds+1):
        t0 = wall_time()

        # train 1 epoca su ciascun client
        for m, xt, yt in zip(models, xtr_s, ytr_s):
            m.fit(xt, yt, epochs=1, batch_size=batch_size, validation_split=0.1, verbose=0)

        # metriche e info peer
        peer_infos = []
        weight_lists = []
        for i, (m, xtest_i, ytest_i) in enumerate(zip(models, xte_s, yte_s)):
            acc_i = evaluate_acc(m, xtest_i, ytest_i)
            w_i = m.get_weights()
            weight_lists.append(w_i)
            h_i = hash_weights(flatten_weights(w_i))
            peer_infos.append(f"peer={i+1}, round={r}, hash={h_i}, accuracy={acc_i:.4f}")

        # FedAvg e valutazione globale (riuso model 0)
        avg_w = average_layerwise(weight_lists)
        for m in models: m.set_weights(avg_w)
        loss_glob, acc_glob = models[0].evaluate(xte, yte, verbose=0)
        test_losses.append(loss_glob); test_accs.append(acc_glob)

        # on-chain: prima i peer, poi l'aggregatore
        for i, info in enumerate(peer_infos):
            w3c.mint_peer_round(r, info, i)

        round_info = {
            "round_id": r,
            "timestamp": utc_timestamp(),
            "duration": wall_time() - t0,
            "participants": num_clients,
            "local_epochs": 1,
            "batch_size": batch_size,
            "avg_round_accuracy": float(np.mean([evaluate_acc(m, xt, yt) for m, xt, yt in zip(models, xtr_s, ytr_s)])),
            "lr": 0.001
        }
        h_avg = hash_weights(flatten_weights(avg_w))
        w3c.mint_aggregator_round(h_avg, json.dumps(round_info))

    return test_losses, test_accs
