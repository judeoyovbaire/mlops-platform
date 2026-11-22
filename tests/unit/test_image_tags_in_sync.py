"""The three pinned pipeline images must share one build SHA.

build-sign-publish tags every image with the short SHA of the commit that
built it, and the tag bumps (#141, #171, #183, #193) move all three at once.
A partial bump leaves a workflow on an image without the code it expects, so
this test fails on the first mismatch.
"""

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

PINNED_IMAGES = {
    "pipelines/training/ml-training-workflow.yaml": "ml-training",
    "pipelines/pretrained/hf-pretrained-workflow.yaml": "hf-pretrained",
    "examples/kserve/transformer-inferenceservice.yaml": "kserve-transformer",
}

IMAGE_REF = re.compile(
    r"ghcr\.io/judeoyovbaire/mlops-platform/(?P<image>[a-z-]+):(?P<tag>[0-9a-f]{7})\b"
)


def _pinned_tags(relative_path: str, image: str) -> set[str]:
    text = (REPO_ROOT / relative_path).read_text()
    return {m.group("tag") for m in IMAGE_REF.finditer(text) if m.group("image") == image}


def _pinned_tag(relative_path: str, image: str) -> str:
    tags = _pinned_tags(relative_path, image)
    assert len(tags) == 1, (
        f"{relative_path}: expected one {image} SHA tag, found {sorted(tags)} (comments count)"
    )
    return tags.pop()


@pytest.mark.parametrize("relative_path, image", PINNED_IMAGES.items())
def test_each_file_pins_exactly_one_sha_tag(relative_path: str, image: str) -> None:
    tags = _pinned_tags(relative_path, image)
    assert len(tags) == 1, (
        f"{relative_path}: expected one {image} SHA tag, found {sorted(tags)} (comments count)"
    )


def test_all_pinned_images_share_one_sha() -> None:
    tags = {path: _pinned_tag(path, image) for path, image in PINNED_IMAGES.items()}
    assert len(set(tags.values())) == 1, f"pinned image tags differ: {tags}"
