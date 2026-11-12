"""Check that an incorrect expected result fails on both built RTL simulators."""

import json
import resource
import struct
import subprocess
from llm_benchmark import BUILD, RESULTS, ROOT, DMEM_BYTES, hexfile


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    data = bytearray(DMEM_BYTES)
    struct.pack_into("<IIII", data, 16, 64, 1, 128, 416)
    data[128:192] = bytes([1]) * 64
    data[416:480] = bytes([1]) * 64
    hexfile(BUILD / "negative.hex", data)
    checks = []
    for name, cmd in (
        ("iverilog", ["vvp", str(BUILD / "iverilog_b1_l1.vvp")]),
        ("verilator", [str(BUILD / "verilator_b1_l1")]),
    ):
        for expected, should_pass in ((64, True), (65, False)):
            p = subprocess.run(
                cmd + ["+DATA=build/llm_bench/negative.hex", f"+EXPECTED={expected}"],
                cwd=ROOT,
                text=True,
                capture_output=True,
                timeout=15,
            )
            output = p.stdout + p.stderr
            if should_pass:
                assert p.returncode == 0 and "PASS llm benchmark" in output, output
            else:
                assert p.returncode != 0 and "Wrong result" in output, output
            checks.append(
                dict(
                    simulator=name,
                    expected=expected,
                    actual=64,
                    correctly_accepted=should_pass,
                    returncode=p.returncode,
                )
            )
    (RESULTS / "failure_detection.json").write_text(json.dumps(checks, indent=2) + "\n")
    print(
        "PASS: both simulators accept 64 and reject an incorrect expected result of 65"
    )


if __name__ == "__main__":
    main()
