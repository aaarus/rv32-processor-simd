"""Compile C kernels, verify real/synthetic vectors on RTL, and save raw measurements."""

import argparse
import csv
import json
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path
from llm_vectors import ROOT, load_cases, reference

BUILD = ROOT / "build/llm_bench"
RESULTS = ROOT / "results/llm"
DMEM_BYTES = 8192
FLAGS = [
    "-march=rv32i",
    "-mabi=ilp32",
    "-mno-relax",
    "-msmall-data-limit=0",
    "-ffixed-x31",
    "-O2",
    "-ffreestanding",
    "-fno-pic",
    "-fno-pie",
    "-fno-stack-protector",
    "-fno-asynchronous-unwind-tables",
]


def run(cmd, log=None):
    p = subprocess.run(
        [str(x) for x in cmd],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    if log:
        (BUILD / log).write_text(p.stdout)
    if p.returncode:
        raise RuntimeError(f"Command failed: {cmd}\n{p.stdout}")
    return p.stdout


def hexfile(path, data):
    assert len(data) > 0 and len(data) % 4 == 0
    path.write_text(
        "".join(
            f"{int.from_bytes(data[i:i+4],'little'):08x}\n"
            for i in range(0, len(data), 4)
        )
    )


def build_program():
    for source in ("start.S", "kernels.c"):
        run(
            [
                "riscv64-unknown-elf-gcc",
                *FLAGS,
                f"-DDMEM_BYTES={DMEM_BYTES}",
                "-c",
                "bench/llm/" + source,
                "-o",
                BUILD / (source + ".o"),
            ]
        )
    elf = BUILD / "program.elf"
    run(
        [
            "riscv64-unknown-elf-gcc",
            *FLAGS,
            "-nostdlib",
            "-Wl,--no-relax,--build-id=none",
            "-T",
            "bench/llm/link.ld",
            BUILD / "start.S.o",
            BUILD / "kernels.c.o",
            "-o",
            elf,
        ]
    )
    run(
        [
            "riscv64-unknown-elf-objcopy",
            "-O",
            "binary",
            "-j",
            ".text",
            elf,
            BUILD / "program.bin",
        ]
    )
    code = (BUILD / "program.bin").read_bytes()
    assert len(code) <= 1024 and len(code) % 4 == 0
    words = [int.from_bytes(code[i : i + 4], "little") for i in range(0, len(code), 4)]
    assert any(w & 0xFE00707F == 0x0B for w in words), "No DOT8 encoding"
    assert any(w & 0xFE00707F == 0x02000033 for w in words), "No MUL encoding"
    (BUILD / "program.dis").write_text(run(["riscv64-unknown-elf-objdump", "-d", elf]))
    hexfile(
        BUILD / "program.hex",
        code + bytes.fromhex("13000000") * ((1024 - len(code)) // 4),
    )
    return len(code)


def simulator(engine, bypass, latency):
    tag = f"{engine}_b{bypass}_l{latency}"
    if engine == "iverilog":
        exe = BUILD / (tag + ".vvp")
        run(
            [
                "iverilog",
                "-g2012",
                "-s",
                "tb_llm_bench",
                f"-Ptb_llm_bench.BYPASS_MODE={bypass}",
                f"-Ptb_llm_bench.MEMORY_LATENCY={latency}",
                f"-Ptb_llm_bench.DMEM_WORDS={DMEM_BYTES//4}",
                "-o",
                exe,
                "-f",
                "rtl/files.f",
                "sim/llm_bench_top.sv",
                "sim/tb_llm_bench.sv",
            ],
            tag + "_compile.log",
        )
        return ["vvp", exe]
    with tempfile.TemporaryDirectory(prefix="llm-rtl-", dir="/tmp") as tmp:
        tmp = Path(tmp)
        shutil.copyfile(ROOT / "sim/llm_bench_main.cpp", tmp / "main.cpp")
        run(
            [
                "verilator",
                "--cc",
                "--exe",
                "-Wno-fatal",
                "--top-module",
                "llm_bench_top",
                f"-GBYPASS_MODE={bypass}",
                f"-GMEMORY_LATENCY={latency}",
                f"-GDMEM_WORDS={DMEM_BYTES//4}",
                "--Mdir",
                tmp,
                "-f",
                "rtl/files.f",
                "sim/llm_bench_top.sv",
                "main.cpp",
            ],
            tag + "_compile.log",
        )
        run(["make", "-C", tmp, "-f", "Vllm_bench_top.mk", "-j2"], tag + "_make.log")
        shutil.copy2(tmp / "Vllm_bench_top", BUILD / tag)
    return [BUILD / tag]


def expected_ops(n, oa, ob, variant):
    if variant == "scalar":
        return n, 0
    prefix = min(n, (-oa) % 4) if oa == ob else 0
    remaining = n - prefix
    return prefix + remaining % 4, remaining // 4


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sim", choices=["verilator", "iverilog"], default="verilator")
    ap.add_argument(
        "--quick", action="store_true", help="Small smoke/cross-simulator set"
    )
    args = ap.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    RESULTS.mkdir(parents=True, exist_ok=True)
    code_size = build_program()
    cases = load_cases()
    if args.quick:
        cases = [
            c
            for c in cases
            if c["id"] in ("random_0", "random_5", "random_64", "lane_order")
        ]
    rows = []
    invocations = 0
    for bypass, latency in ((1, 1), (0, 1), (0, 5)):
        cmd = simulator(args.sim, bypass, latency)
        for case in cases:
            n = len(case["a"])
            # Equal and differing misalignment, plus deliberate cache conflicts.
            # Preserve cache-index relationships while fitting whole vectors.
            base = 128 + ((max(n, 256) + 63) // 64) * 64
            layouts = [(0, 0, base + 32, "shifted")]
            if case["id"] in ("random_5", "random_64", "lane_order"):
                layouts += [(1, 1, base + 32, "shifted"), (1, 2, base + 32, "shifted")]
            if n in (64, 256, 1024, 2048):
                layouts += [(0, 0, base, "conflict")]
            for oa, ob, base, layout in layouts:
                for variant in ("scalar", "dot8"):
                    total_results = [0, 0]
                    # One uninterrupted invocation, including the complete real rows.
                    for chunk in (0,):
                        a = case["a"]
                        b = case["b"]
                        expected = reference(a, b)
                        data = bytearray(DMEM_BYTES)
                        pa, pb = 128 + oa, base + ob
                        assert pa + len(a) <= pb and pb + len(b) <= DMEM_BYTES - 256
                        struct.pack_into(
                            "<IIII", data, 16, len(a), int(variant == "dot8"), pa, pb
                        )
                        data[pa : pa + len(a)] = bytes(x & 255 for x in a)
                        data[pb : pb + len(b)] = bytes(x & 255 for x in b)
                        hexfile(BUILD / "input.hex", data)
                        output = run(
                            [
                                *cmd,
                                "+DATA=build/llm_bench/input.hex",
                                f"+EXPECTED={expected}",
                            ]
                        )
                        measures = [
                            list(map(int, line.split(",")[1:]))
                            for line in output.splitlines()
                            if line.startswith("MEASURE,")
                        ]
                        if len(measures) != 2 or "PASS llm benchmark" not in output:
                            raise AssertionError(output)
                        for m in measures:
                            (
                                repeat,
                                cycles,
                                instructions,
                                muls,
                                dots,
                                holds,
                                bubbles,
                                total,
                                value,
                            ) = m
                            assert value == expected
                            assert (muls, dots) == expected_ops(
                                len(a), oa, ob, variant
                            ), (case["id"], m)
                            total_results[repeat] += value
                            rows.append(
                                dict(
                                    case=case["id"],
                                    source=case["source"],
                                    length=n,
                                    chunk=chunk,
                                    chunk_length=len(a),
                                    data_memory_bytes=DMEM_BYTES,
                                    address_a=pa,
                                    address_b=pb,
                                    variant=variant,
                                    mode="bypass" if bypass else "cached",
                                    latency=latency,
                                    layout=layout,
                                    offset_a=oa,
                                    offset_b=ob,
                                    repeat=repeat,
                                    cycles=cycles,
                                    instructions=instructions,
                                    muls=muls,
                                    dots=dots,
                                    cache_stalls=holds,
                                    load_use=bubbles,
                                    cycles_since_reset=total,
                                    result=value,
                                    cycles_per_element=cycles / len(a) if a else "",
                                )
                            )
                        invocations += 2
                    assert total_results == [case["expected"]] * 2
        print(f"PASS {args.sim}: bypass={bypass} latency={latency}", flush=True)
    stem = args.sim + ("_quick" if args.quick else "")
    with (RESULTS / (stem + ".csv")).open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    summary = dict(
        engine=args.sim,
        code_bytes=code_size,
        cases=len(cases),
        data_memory_bytes=DMEM_BYTES,
        chunked=False,
        verified_kernel_invocations=invocations,
        rows=len(rows),
        compiler=run(["riscv64-unknown-elf-gcc", "--version"]).splitlines()[0],
        simulator=run(
            [args.sim, "--version"] if args.sim == "verilator" else ["iverilog", "-V"]
        ).splitlines()[0],
    )
    (RESULTS / (stem + ".json")).write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
