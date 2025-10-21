import numpy as np
from federated.utils import hash_weights, flatten_weights
from federated.model_manager import average_layerwise

def test_hash_deterministic():
    a = np.arange(10)
    h1 = hash_weights(a)
    h2 = hash_weights(a)
    assert h1 == h2

def test_fedavg_shapes():
    w1 = [np.ones((2,2)), np.ones((2,))]
    w2 = [np.zeros((2,2)), np.zeros((2,))]
    avg = average_layerwise([w1, w2])
    assert avg[0].shape == (2,2) and avg[1].shape == (2,)
