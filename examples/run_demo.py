import os
from federated.training_orchestrator import run_federated

if __name__ == "__main__":
    rounds = int(os.getenv("ROUNDS", "1"))
    print(f"Starting federated demo ({rounds} round{'s' if rounds != 1 else ''})…")
    losses, accs = run_federated(rounds=rounds)
    print(f"Done. Test accuracy after round {rounds}:", accs[-1])
