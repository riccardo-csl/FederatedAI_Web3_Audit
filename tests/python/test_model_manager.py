import numpy as np

from federated.model_manager import build_client_model, evaluate_acc, average_layerwise


def test_average_layerwise_values():
    w1 = [np.array([[1., 3.]]), np.array([2.])]
    w2 = [np.array([[3., 1.]]), np.array([4.])]
    avg = average_layerwise([w1, w2])
    np.testing.assert_allclose(avg[0], np.array([[2., 2.]]))
    np.testing.assert_allclose(avg[1], np.array([3.]))


def test_build_and_evaluate_model_shape_and_metric():
    model = build_client_model(input_shape=(28, 28), n_classes=10)
    x = np.zeros((2, 28, 28), dtype="float32")
    y = np.zeros((2,), dtype="int64")
    acc = evaluate_acc(model, x, y)
    assert 0.0 <= acc <= 1.0

