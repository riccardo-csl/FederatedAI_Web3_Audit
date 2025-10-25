from tensorflow import keras
from tensorflow.keras import layers
import numpy as np

def build_client_model(input_shape=(28,28), n_classes=10):
    model = keras.Sequential([
        keras.Input(shape=input_shape),
        layers.Flatten(),
        layers.Dense(128, activation="relu"),
        layers.Dense(64, activation="relu"),
        layers.Dense(n_classes, activation="softmax"),
    ])
    model.compile(
        loss="sparse_categorical_crossentropy",
        optimizer="adam",
        metrics=["accuracy"]
    )
    return model

def evaluate_acc(model, x, y) -> float:
    _, acc = model.evaluate(x, y, verbose=0)
    return float(acc)

def average_layerwise(list_of_weight_lists: list[list[np.ndarray]]) -> list[np.ndarray]:
    num_layers = len(list_of_weight_lists[0])
    out = []
    for l in range(num_layers):
        arrs = [w[l] for w in list_of_weight_lists]
        out.append(np.mean(arrs, axis=0))
    return out
