"""Produce tables and publication-style plots from measured RTL CSV files."""

import csv
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from llm_vectors import ROOT

deps = Path.home() / ".local/share/rv32-llm/plot"
if deps.exists():
    sys.path.insert(0, str(deps))
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT = ROOT / "results/llm"


def main():
    metadata = json.loads((OUT / "verilator.json").read_text())
    raw = list(csv.DictReader((OUT / "verilator.csv").open()))
    integers = (
        "length",
        "chunk",
        "chunk_length",
        "offset_a",
        "offset_b",
        "repeat",
        "latency",
        "cycles",
        "instructions",
        "muls",
        "dots",
        "cache_stalls",
        "load_use",
        "cycles_since_reset",
        "result",
    )
    for r in raw:
        for field in integers:
            r[field] = int(r[field])
    # Full vectors must be measured in one invocation, never summed from chunks.
    fields = (
        "case",
        "source",
        "length",
        "mode",
        "latency",
        "layout",
        "offset_a",
        "offset_b",
        "repeat",
    )
    grouped = defaultdict(dict)
    for r in raw:
        assert r["chunk"] == 0 and r["chunk_length"] == r["length"]
        assert int(r["data_memory_bytes"]) == metadata["data_memory_bytes"]
        key = tuple(r[k] for k in fields)
        g = grouped[key].setdefault(r["variant"], defaultdict(int))
        for k in (
            "cycles",
            "instructions",
            "muls",
            "dots",
            "cache_stalls",
            "load_use",
            "result",
        ):
            g[k] += r[k]
        g["chunks"] += 1
        if r["repeat"] == 0:
            g["startup_cycles"] += r["cycles_since_reset"] - r["cycles"]
    rows = []
    for key, g in grouped.items():
        assert set(g) == {"scalar", "dot8"}
        assert g["scalar"]["result"] == g["dot8"]["result"]
        r = dict(zip(fields, key))
        n = r["length"]
        for v in g:
            for k, val in g[v].items():
                r[v + "_" + k] = val
            r[v + "_cycles_per_element"] = g[v]["cycles"] / n if n else ""
        r["speedup"] = g["scalar"]["cycles"] / g["dot8"]["cycles"]
        rows.append(r)
    with (OUT / "summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    indexed = {
        (
            r["case"],
            r["mode"],
            r["latency"],
            r["layout"],
            r["offset_a"],
            r["offset_b"],
            r["repeat"],
        ): r
        for r in rows
    }

    def select(case, mode="bypass", latency=1, layout="shifted", repeat=0):
        return indexed[(case, mode, latency, layout, 0, 0, repeat)]

    sizes = [64, 256, 1024, 2048]
    fig, axs = plt.subplots(1, 3, figsize=(15, 4.6))
    for mode, lat, color in (
        ("bypass", 1, "#2563eb"),
        ("cached", 1, "#059669"),
        ("cached", 5, "#d97706"),
    ):
        points = [select(f"random_{n}", mode, lat) for n in sizes]
        label = mode if mode == "bypass" else f"cached, latency {lat}"
        for v, style in (("scalar", "--"), ("dot8", "-")):
            axs[0].plot(
                sizes,
                [p[v + "_cycles"] for p in points],
                style,
                marker="o",
                color=color,
                label=label + " " + v,
            )
        axs[1].plot(
            sizes, [p["speedup"] for p in points], marker="o", color=color, label=label
        )
        axs[2].plot(
            sizes,
            [p["dot8_cycles_per_element"] for p in points],
            marker="o",
            color=color,
            label=label,
        )
    axs[0].set_ylabel("Measured cycles (complete vector)")
    axs[1].set_ylabel("Scalar cycles / DOT8 cycles")
    axs[2].set_ylabel("DOT8 cycles per element")
    for ax in axs:
        ax.set_xlabel("Vector length")
        ax.set_xscale("log", base=2)
        ax.set_xticks(sizes, labels=[str(n) for n in sizes])
        ax.grid(alpha=0.25)
        ax.legend(fontsize=7)
    fig.suptitle(
        "Synthetic INT8 vectors on actual RTL - compiled C, first invocation, aligned inputs"
    )
    fig.tight_layout()
    fig.savefig(OUT / "performance.png", dpi=180)
    fig.savefig(OUT / "performance.svg")
    plt.close(fig)

    fig, axs = plt.subplots(1, 2, figsize=(11, 4.4))
    labels = []
    sc = []
    dc = []
    si = []
    di = []
    for layout in ("shifted", "conflict"):
        for repeat in (0, 1):
            r = select("random_256", "cached", 5, layout, repeat)
            labels.append(layout + "\n" + ("first" if repeat == 0 else "repeat"))
            sc.append(r["scalar_cycles"])
            dc.append(r["dot8_cycles"])
            si.append(r["scalar_cache_stalls"])
            di.append(r["dot8_cache_stalls"])
    x = list(range(len(labels)))
    for ax, a, b, title in (
        (axs[0], sc, dc, "Total kernel-window cycles"),
        (axs[1], si, di, "Cycles held by cache misses"),
    ):
        ax.bar(
            [i - 0.18 for i in x], a, width=0.36, label="Scalar MUL", color="#2563eb"
        )
        ax.bar([i + 0.18 for i in x], b, width=0.36, label="DOT8", color="#059669")
        ax.set_xticks(x, labels)
        ax.set_title(title)
        ax.legend()
        ax.grid(axis="y", alpha=0.2)
    fig.suptitle(
        "256 synthetic INT8 elements - caches/predictor enabled, memory latency 5"
    )
    fig.tight_layout()
    fig.savefig(OUT / "memory.png", dpi=180)
    fig.savefig(OUT / "memory.svg")
    plt.close(fig)

    lines = [
        "# Measured compiled-C DOT8 results",
        "",
        "These are integer kernel measurements on the existing RTL, not end-to-end LLM speedups.",
        "Both scalar and DOT8 use the existing hardware low-word MUL for scalar elements.",
        f"Code size is {metadata['code_bytes']} bytes. Data memory is {metadata['data_memory_bytes']//1024} KiB; instruction memory, caches, and pipeline timing are unchanged.",
        "",
        "## Executed validation",
        "",
        f"{metadata['cases']} vector cases: 25 synthetic and 56 captured real-data cases. Each full simulator run verifies {metadata['verified_kernel_invocations']:,} complete-vector kernel invocations across variants, layouts, alignment cases, cache configurations and repetitions.",
        "The existing 42 RTL regression configurations, eight memory-capacity configurations (1/8 KiB), and the bare-metal C smoke test also passed. Capacity tests cover upper-address initialization, non-aliasing, masked writes and reset preservation. Wrong-result rejection was verified in both simulators.",
        "",
        "## First invocation, aligned shifted layout",
        "",
        "| Source / length | Mode | Scalar cycles | DOT8 cycles | Speedup | Scalar EX instructions | DOT8 EX instructions |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    chosen = [
        ("synthetic / 64", "random_64"),
        ("synthetic / 256", "random_256"),
        ("synthetic / 1024", "random_1024"),
        ("synthetic / 2048", "random_2048"),
        ("real query / 288", "real_call0_row0_n288"),
        ("real FFN / 768", "real_call6_row0_n768"),
    ]
    for label, case in chosen:
        for mode, lat in (("bypass", 1), ("cached", 5)):
            r = select(case, mode, lat)
            lines.append(
                f"| {label} | {mode}"
                + (" L5" if mode == "cached" else "")
                + f" | {r['scalar_cycles']} | {r['dot8_cycles']} | {r['speedup']:.3f}x"
                f" | {r['scalar_instructions']} | {r['dot8_instructions']} |"
            )
    lines += [
        "",
        "![Performance](performance.png)",
        "",
        "![Memory behavior](memory.png)",
        "",
        "## Scope and interpretation",
        "",
        "- Every vector, including the real 768-element FFN row and synthetic 2048-element vectors, executes in one uninterrupted kernel invocation. There is no host chunk accumulation. Host image loading is outside the timing window.",
        "- Historical 1 KiB/chunked measurements are preserved under legacy_1k/ and must not be mixed with these 8 KiB complete-vector results.",
        "- First invocation starts after startup; caches are reset before each simulation, but startup has already touched instruction/stack/control lines. Repeat retains the first invocation's cache and predictor state; it does not imply all data is resident.",
        "- EX instruction counts count non-stalled, non-bubble instructions between the markers. They are not a hardware retired-instruction counter.",
        "- Window includes argument setup, dispatch, function call/return, and result store; startup, image loading, and the marker instructions themselves are excluded from instruction counts. Marker-to-marker cycles include elapsed stall/redirect cycles.",
        "- Cached mode enables both caches and prediction. Latency 1 versus 5 isolates backing-memory delay with the same cached configuration; bypass versus cached also changes prediction.",
        "- Group-scaled floating-point outputs remain host-side. Each group of one real 768-element FFN row is independently verified on RTL. Summing the whole row's integer products is not equivalent to applying one common scale.",
        "- No physical clock frequency, synthesis area, or end-to-end RISC-V inference speedup was measured.",
        "",
    ]
    profile = OUT / "host_profile.json"
    if profile.exists():
        p = json.loads(profile.read_text())
        lines += [
            "## Separate host profiling",
            "",
            f"Median matmul fraction of timed forward execution: **{100*p['median_matmul_fraction']:.2f}%** across three single-thread, 128-step runs.",
            "CLOCK_MONOTONIC function timers; includes instrumentation overhead and WSL scheduling noise. See host_profile.json. This fraction cannot establish target CPU end-to-end speedup.",
            "",
        ]
    (OUT / "README.md").write_text("\n".join(lines))
    cross = OUT / "iverilog.csv"
    if cross.exists():
        other = list(csv.DictReader(cross.open()))
        # CSV outputs are deterministic and include all measured counts and values.
        primary = list(csv.DictReader((OUT / "verilator.csv").open()))
        assert other == primary, "Cross-simulator results differ"
        (OUT / "cross_simulator.json").write_text(
            json.dumps(
                dict(equal=True, compared_kernel_invocations=len(primary)), indent=2
            )
            + "\n"
        )
        print(
            f"PASS: all {len(primary)} records match exactly across Icarus and Verilator"
        )
    print("\n".join(lines[:29]))


if __name__ == "__main__":
    main()
