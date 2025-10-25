import numpy as np

from federated.data_handler import split_among_clients


def test_split_among_clients_equal_chunks():
    n = 100
    x = np.arange(n*4, dtype=np.float32).reshape(n, 2, 2)
    y = np.arange(n, dtype=np.int64)
    num_clients = 7
    xs, ys = split_among_clients(x, y, num_clients=num_clients)

    chunk = n // num_clients
    assert len(xs) == num_clients and len(ys) == num_clients
    assert all(xi.shape[0] == chunk for xi in xs)
    assert all(yi.shape[0] == chunk for yi in ys)

    covered = sum(xi.shape[0] for xi in xs)
    assert covered == chunk * num_clients <= n

