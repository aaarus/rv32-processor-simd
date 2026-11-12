"""Single-thread host profile with monotonic timers; separate from RTL measurements."""

import json
import os
from pathlib import Path
import statistics
import subprocess
from llm_vectors import ROOT

WORK = ROOT / "build/llm_reference"


def run(cmd, log):
    p = subprocess.run(
        [str(x) for x in cmd], cwd=ROOT, capture_output=True, text=True, timeout=180
    )
    (WORK / log).write_text(p.stdout + "\n" + p.stderr)
    if p.returncode:
        raise RuntimeError(p.stderr)
    return p


def main():
    source = (WORK / "llama2.c/runq.c").read_text()
    helper = r"""
static double prof_ns[5]={0};
static unsigned long prof_calls[5]={0};
static double prof_clock(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC,&t);
    return (double)t.tv_sec*1e9+(double)t.tv_nsec;
}
static void prof_report(void) {
    fprintf(stderr,"PROFILE,{\"matmul_ns\":%.0f,\"rmsnorm_ns\":%.0f,"
        "\"softmax_ns\":%.0f,\"quantize_ns\":%.0f,\"forward_ns\":%.0f,"
        "\"forward_calls\":%lu}\n",prof_ns[0],prof_ns[1],prof_ns[2],
        prof_ns[3],prof_ns[4],prof_calls[4]);
}
"""
    source = source.replace("int GS = 0;", helper + "\nint GS = 0;")
    functions = [
        (
            "void matmul(float* xout, QuantizedTensor *x, QuantizedTensor *w, int n, int d)",
            "matmul",
            "xout,x,w,n,d",
            "void",
            0,
        ),
        (
            "void rmsnorm(float* o, float* x, float* weight, int size)",
            "rmsnorm",
            "o,x,weight,size",
            "void",
            1,
        ),
        ("void softmax(float* x, int size)", "softmax", "x,size", "void", 2),
        (
            "void quantize(QuantizedTensor *qx, float* x, int n)",
            "quantize",
            "qx,x,n",
            "void",
            3,
        ),
        (
            "float* forward(Transformer* transformer, int token, int pos)",
            "forward",
            "transformer,token,pos",
            "float*",
            4,
        ),
    ]
    for signature, name, args, ret, index in functions:
        assert source.count(signature + " {") == 1
        start = source.index(signature + " {")
        end = source.index("\n}", start) + 2
        body = source[start:end].replace(name + "(", name + "_original(", 1)
        wrapper = signature + " {\n"
        if index == 4:
            wrapper += "    if (!prof_calls[4]) atexit(prof_report);\n"
        wrapper += "    double begin=prof_clock();\n"
        wrapper += (
            f"    {'float *answer=' if ret!='void' else ''}{name}_original({args});\n"
        )
        wrapper += f"    prof_ns[{index}]+=prof_clock()-begin; prof_calls[{index}]++;\n"
        if ret != "void":
            wrapper += "    return answer;\n"
        wrapper += "}\n"
        source = source[:start] + body + "\n" + wrapper + source[end:]
    (WORK / "runq_profile.c").write_text(source)
    run(
        ["gcc", "-O2", WORK / "runq_profile.c", "-lm", "-o", WORK / "runq_profile"],
        "build_profile.log",
    )
    flags = [
        WORK / "stories15M-q80.bin",
        "-z",
        WORK / "llama2.c/tokenizer.bin",
        "-t",
        "0",
        "-s",
        "1",
        "-n",
        "128",
        "-i",
        "Once upon a time",
    ]
    baseline = run([WORK / "runq", *flags], "profile_baseline.log").stdout
    measurements = []
    for repeat in range(3):
        result = run([WORK / "runq_profile", *flags], f"profile_{repeat}.log")
        assert result.stdout == baseline, "Profile instrumentation changed text"
        record = json.loads(
            next(
                x[len("PROFILE,") :]
                for x in result.stderr.splitlines()
                if x.startswith("PROFILE,")
            )
        )
        record["other_forward_ns"] = record["forward_ns"] - sum(
            record[k] for k in ("matmul_ns", "rmsnorm_ns", "softmax_ns", "quantize_ns")
        )
        record["matmul_fraction"] = record["matmul_ns"] / record["forward_ns"]
        measurements.append(record)
    report = dict(
        method="CLOCK_MONOTONIC function timers, single thread, gcc -O2; three runs",
        caveat="Instrumented host timings include timer overhead and WSL scheduling noise. "
        "Other forward includes attention loops, nonlinear activation loops, RoPE, residuals and timer overhead. "
        "Host percentages are not RISC-V end-to-end speedups.",
        measurements=measurements,
        median_matmul_fraction=statistics.median(
            x["matmul_fraction"] for x in measurements
        ),
    )
    out = ROOT / "results/llm"
    out.mkdir(exist_ok=True, parents=True)
    (out / "host_profile.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
