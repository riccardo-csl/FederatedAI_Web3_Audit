from federated.training_orchestrator import run_federated

if __name__ == "__main__":
    print("Starting federated demo (1 round)…")
    losses, accs = run_federated(rounds=10)
    print("Done. Test accuracy after round 1:", accs[-1])
