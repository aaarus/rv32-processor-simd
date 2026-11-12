"""Fetch pinned llama2.c, export TinyStories Q8_0, and capture real matmul operands.
Install CPU torch/numpy first (see docs/llm-benchmark.md). Large files stay in build/.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import urllib.request
from llm_vectors import ROOT, reference

REV = "350e04fe35433e6d2941dce5a1f53308f87058eb"
URL = "https://huggingface.co/karpathy/tinyllamas/resolve/main/stories15M.pt"
CHECKPOINT_SHA256 = "3da00c0fef684f3f83b457736837c46ab55e92a26662b61d6104de2d271c708d"
WORK = ROOT / "build/llm_reference"
REPO = WORK / "llama2.c"


def run(args, log, env=None):
    p = subprocess.run(
        [str(x) for x in args],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=600,
    )
    (WORK / log).write_text(p.stdout + "\n" + p.stderr)
    if p.returncode:
        raise RuntimeError(p.stdout + p.stderr)
    return p.stdout


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--skip-export",
        action="store_true",
        help="Reuse an already exported checkpoint",
    )
    args = ap.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    if not REPO.exists():
        run(
            ["git", "clone", "https://github.com/karpathy/llama2.c.git", REPO],
            "clone.log",
        )
        run(["git", "-C", REPO, "checkout", "--detach", REV], "checkout.log")
    rev = run(["git", "-C", REPO, "rev-parse", "HEAD"], "revision.log").strip()
    if rev != REV:
        raise SystemExit(
            f"Expected upstream revision {REV}; found {rev}. Use a separate clean pinned checkout."
        )
    checkpoint = WORK / "stories15M.pt"
    if not checkpoint.exists():
        urllib.request.urlretrieve(URL, checkpoint)
    if sha(checkpoint) != CHECKPOINT_SHA256:
        raise SystemExit(
            "Checkpoint checksum differs from the verified TinyStories input"
        )
    quant = WORK / "stories15M-q80.bin"
    env = os.environ.copy()
    deps = Path.home() / ".local/share/rv32-llm/python"
    if deps.exists():
        env["PYTHONPATH"] = str(deps) + os.pathsep + env.get("PYTHONPATH", "")
    env["OMP_NUM_THREADS"] = "2"
    if not args.skip_export:
        run(
            [
                sys.executable,
                REPO / "export.py",
                quant,
                "--version",
                "2",
                "--checkpoint",
                checkpoint,
            ],
            "export.log",
            env,
        )
    with quant.open("rb") as f:
        header = f.read(256)
    magic, version, *dims = struct.unpack_from("<9i", header)
    gs = struct.unpack_from("<i", header, 37)[0]
    if magic != 0x616B3432 or version != 2 or dims[2] != 6:
        raise ValueError("Wrong format/model for this capture selection")
    source = (REPO / "runq.c").read_text()
    signature = "void matmul(float* xout, QuantizedTensor *x, QuantizedTensor *w, int n, int d) {"
    assert source.count(signature) == 1
    source = source.replace(signature, signature.replace("matmul(", "matmul_original("))
    marker = "float* forward(Transformer* transformer, int token, int pos) {"
    assert source.count(marker) == 1
    source = source.replace(
        marker, (ROOT / "bench/llm/capture_hook.c").read_text() + "\n" + marker
    )
    (WORK / "runq_capture.c").write_text(source)
    run(
        ["gcc", "-O2", REPO / "runq.c", "-lm", "-o", WORK / "runq"],
        "build_original.log",
    )
    run(
        ["gcc", "-O2", WORK / "runq_capture.c", "-lm", "-o", WORK / "runq_capture"],
        "build_capture.log",
    )
    flags = [
        quant,
        "-z",
        REPO / "tokenizer.bin",
        "-t",
        "0",
        "-s",
        "1",
        "-n",
        "16",
        "-i",
        "Once upon a time",
    ]
    original = run([WORK / "runq", *flags], "original_inference.log", env)
    raw = WORK / "capture.jsonl"
    raw.write_text("")
    env["LLM_CAPTURE"] = str(raw)
    captured = run([WORK / "runq_capture", *flags], "captured_inference.log", env)
    if original != captured:
        raise AssertionError("Instrumentation changed generated text")
    records = [json.loads(line) for line in raw.read_text().splitlines()]
    if len(records) != 8:
        raise AssertionError(f"Expected eight real rows, got {len(records)}")
    vectors = []
    for r in records:
        n = r["n"]
        group = r["group_size"]
        assert n % group == 0 and group == gs
        partials = [
            reference(r["a"][i : i + group], r["b"][i : i + group])
            for i in range(0, n, group)
        ]
        scaled = 0.0
        for dot, ws, xs in zip(partials, r["weight_scales"], r["activation_scales"]):
            scaled = f32(scaled + f32(f32(float(dot) * f32(ws)) * f32(xs)))
        if abs(scaled - r["scaled_output"]) > 1e-6 * max(1, abs(scaled)):
            raise AssertionError("Scaled reference differs from runq output")
        r["group_integer_results"] = partials
        r["reconstructed_scaled_output"] = scaled
        # Prefixes are real slices, not fabricated wider rows.
        for length in sorted(set((group, 64, 256, n))):
            if length > n:
                continue
            a, b = r["a"][:length], r["b"][:length]
            vectors.append(
                dict(
                    id=f"real_call{r['call']}_row{r['row']}_n{length}",
                    source="real_llm",
                    a=a,
                    b=b,
                    expected=reference(a, b),
                    original_dimensions=[r["d"], n],
                    row=r["row"],
                    call=r["call"],
                    group_size=group,
                    weight_scales=r["weight_scales"][: length // group],
                    activation_scales=r["activation_scales"][: length // group],
                    group_integer_results=partials[: length // group],
                )
            )
        # Verify every group of one complete FFN row on RTL, not only the row sum.
        if r["call"] == 6 and r["row"] == 0:
            for g, dot in enumerate(partials):
                lo = g * group
                vectors.append(
                    dict(
                        id=f"real_group_{g}",
                        source="real_llm",
                        a=r["a"][lo : lo + group],
                        b=r["b"][lo : lo + group],
                        expected=dot,
                        group_size=group,
                        call=6,
                        row=0,
                        group=g,
                        weight_scale=r["weight_scales"][g],
                        activation_scale=r["activation_scales"][g],
                    )
                )
    provenance = dict(
        upstream="https://github.com/karpathy/llama2.c",
        revision=rev,
        checkpoint_url=URL,
        checkpoint_sha256=sha(checkpoint),
        quantized_sha256=sha(quant),
        config=dict(
            zip(
                [
                    "dim",
                    "hidden_dim",
                    "layers",
                    "heads",
                    "kv_heads",
                    "vocab",
                    "sequence_length",
                ],
                dims,
            )
        ),
        group_size=gs,
        prompt="Once upon a time",
        steps=16,
        temperature=0,
        seed=1,
        instrumentation_text_equal=True,
    )
    out = ROOT / "bench/llm/vectors"
    out.mkdir(parents=True, exist_ok=True)
    (out / "real.json").write_text(
        json.dumps(
            dict(provenance=provenance, captures=records, vectors=vectors), indent=2
        )
        + "\n"
    )
    print(json.dumps(provenance, indent=2))
    print(
        f"Captured {len(records)} rows; generated {len(vectors)} exact real test cases."
    )


if __name__ == "__main__":
    main()
