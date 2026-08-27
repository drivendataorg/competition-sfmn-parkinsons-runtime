import importlib
import platform
import subprocess

import pytest

packages = [
    "accelerate",
    "attrs",
    "certifi",
    "cloudpickle",
    "dill",
    "diskcache",
    "einops",
    "filelock",
    "fsspec",
    "huggingface_hub",
    "importlib_metadata",
    "jsonpickle",
    "lightgbm",
    "loguru",
    "matplotlib",
    "monai",
    "more_itertools",
    "nibabel",
    "ninja",
    "numba",
    "numpy",
    "cv2",
    "packaging",
    "pandas",
    "peft",
    "PIL",
    "polars",
    "psutil",
    "pydantic_settings",
    "pydantic",
    "pytorch_lightning",
    "yaml",
    "regex",
    "requests",
    "safetensors",
    "skimage",
    "sklearn",
    "scipy",
    "SimpleITK",
    "statsmodels",
    "timm",
    "tokenizers",
    "torch",
    "torchio",
    "torchvision",
    "tqdm",
    "transformers",
    "urllib3",
    "xarray",
    "tensorflow",
]


def is_gpu_available():
    try:
        return subprocess.check_call(["nvidia-smi"]) == 0

    except FileNotFoundError:
        return False


GPU_AVAILABLE = is_gpu_available()
IS_X86_64 = platform.machine() in ("x86_64", "AMD64")


@pytest.mark.parametrize("package_name", packages, ids=packages)
def test_import(package_name):
    """Test that certain dependencies are importable."""
    importlib.import_module(package_name)


@pytest.mark.skipif(
    not IS_X86_64, reason="antspyx wheels are only published for x86_64"
)
def test_import_antspyx():
    """Test that antspyx is importable (only installed on x86_64)."""
    importlib.import_module("ants")


@pytest.mark.skipif(not GPU_AVAILABLE, reason="No GPU available")
def test_torch_cuda_available():
    """Test that PyTorch can see CUDA."""
    import torch

    assert torch.cuda.is_available(), "CUDA should be available"


@pytest.mark.skipif(not GPU_AVAILABLE, reason="No GPU available")
def test_torch_allocate_tensor():
    """Test that PyTorch can allocate a tensor on GPU."""
    import torch

    tensor = torch.zeros(1).cuda()
    assert tensor.device.type == "cuda"


@pytest.mark.skipif(not GPU_AVAILABLE, reason="No GPU available")
def test_tensorflow_gpu_available():
    """Test whether tensorflow is using the available GPU"""
    
    import tensorflow as tf
    
    tf.debugging.set_log_device_placement(True)
    
    a = tf.constant([[1.0, 2.0], [3.0, 4.0]])
    b = tf.constant([[1.0, 1.0], [0.1, 0.2]])
    c = tf.matmul(a, b)
    assert 'GPU' in c.device
