"""Deterministic vectors and strict, independent integer references."""

import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def reference(a, b):
    if len(a) != len(b) or any(not -128 <= v <= 127 for v in a + b):
        raise ValueError("Invalid signed INT8 vectors")
    result = sum(int(x) * int(y) for x, y in zip(a, b))
    if not -(1 << 31) <= result < (1 << 31):
        raise ValueError("Reference exceeds INT32")
    return result


def synthetic():
    rng = random.Random(20261102)
    cases = []
    for n in (
        0,
        1,
        2,
        3,
        4,
        5,
        7,
        15,
        31,
        32,
        63,
        64,
        65,
        127,
        128,
        255,
        256,
        257,
        1024,
        2048,
    ):
        a = [rng.randrange(-128, 128) for _ in range(n)]
        b = [rng.randrange(-128, 128) for _ in range(n)]
        cases.append(dict(id=f"random_{n}", source="synthetic", a=a, b=b))
    for name, a, b in [
        ("zero", [0] * 64, [127] * 64),
        ("min_min", [-128] * 64, [-128] * 64),
        ("min_max", [-128] * 64, [127] * 64),
        ("lane_order", [-128, -1, 0, 1, 127] * 13, [1, 127, -128, 0, -1] * 13),
    ]:
        cases.append(dict(id=name, source="synthetic", a=a, b=b))
    # All extreme operand pairs exercise signs and mixed lanes independently.
    vals = [-128, -1, 0, 1, 127]
    cases.append(
        dict(
            id="extreme_pairs",
            source="synthetic",
            a=[x for x in vals for y in vals],
            b=[y for x in vals for y in vals],
        )
    )
    for case in cases:
        case["expected"] = reference(case["a"], case["b"])
    return cases


def load_cases():
    cases = synthetic()
    real = ROOT / "bench/llm/vectors/real.json"
    if real.exists():
        cases += json.loads(real.read_text())["vectors"]
    for case in cases:
        assert reference(case["a"], case["b"]) == case["expected"], case["id"]
    return cases


if __name__ == "__main__":
    out = ROOT / "bench/llm/vectors"
    out.mkdir(parents=True, exist_ok=True)
    (out / "synthetic.json").write_text(
        json.dumps({"seed": 20261102, "vectors": synthetic()}, indent=2) + "\n"
    )
    print(f"Wrote {len(synthetic())} synthetic cases")
