import numpy as np
from tensorflow import keras

def load_mnist_normalized():
    (x_train, y_train), (x_test, y_test) = keras.datasets.mnist.load_data()
    x_train = x_train.astype("float32") / 255.0
    x_test  = x_test.astype("float32") / 255.0
    return (x_train, y_train), (x_test, y_test)

def split_among_clients(x, y, num_clients=5):
    n = x.shape[0]
    idx = np.random.permutation(n)
    x, y = x[idx], y[idx]
    chunk = n // num_clients
    xs, ys = [], []
    for i in range(num_clients):
        xs.append(x[i*chunk:(i+1)*chunk])
        ys.append(y[i*chunk:(i+1)*chunk])
    return xs, ys
