# RISC-V DOT8 acceleration of a quantized LLM kernel

## Outcome and scope

This project compiles C scalar and DOT8 INT8 dot-product kernels and executes
them on the actual five-stage RTL. It captures weights and activations from
Karpathy's quantized llama2.c inference, checks exact integer results, and measures
kernel-window cycles and executed instructions. It does not run the full
Transformer on this processor.

The measured tables and plots are in [results/llm/README.md](../results/llm/README.md).
The large checkpoints and upstream checkout remain under ignored build/ storage.

## Verified architecture and baseline

- Five stages: fetch, decode, execute, memory, writeback.
- Top/decoder: rtl/core/top.v and control_unit.v; ALU: alu.v.
- Pipeline registers: rtl/pipeline/; integer register file: rtl/core/reg_bank.v.
- DOT8: rtl/core/dot8.v, selected in EX through ordinary forwarding/writeback.
- Integer ALU, signed/subword loads, stores, branches, LUI/AUIPC, JAL/JALR.
- Hardware low-word MUL exists. MULH/MULHU/MULHSU, DIV/REM, compressed, FPU,
  traps, CSRs, interrupts, ECALL, and FENCE are not implemented.
- Instruction memory: 256 words (1 KiB). Data memory is parameterized through
  top.DMEM_WORDS, defaults to 256 words, and uses 2048 words (8 KiB) for this
  benchmark. Addresses outside the configured range alias; software must stay in range.
- I-cache and D-cache: 16 direct-mapped one-word lines each. D-cache uses write-back,
  write-allocate. A 64-entry branch predictor can be bypassed separately.
- Cache misses freeze the pipeline. Forwarding and load-use interlocks remain
  active in bypass mode.
- IMEM_INIT_FILE and DMEM_INIT_FILE load little-endian word-oriented hex images.
- Existing C flow uses return/completion words at addresses 0/4. Its startup
  sets SP, zeroes BSS, and calls main. Data/constants are preloaded by simulation.
- All 42 existing regression configurations pass, including the independent
  arithmetic test's 75,542 operand pairs. Existing C executes in both simulators.

Data-memory capacity is now configurable; array depth and address-index width
grow together. Pipeline, cache sizes, memory latency, decoder and DOT8 behavior
are unchanged. The benchmark wrapper only observes internal signals.

## Prerequisites and commands

Run commands in WSL/Linux from the repository root. Tools used:

- RISC-V bare-metal GCC 10.2.0 and binutils.
- Icarus 11.0.
- Verilator 4.038, GNU Make, g++.
- Python 3.10, host GCC.
- Optional host export dependencies: CPU PyTorch 2.14.1+cpu, NumPy 2.2.6.
- Plotting: Matplotlib 3.10.9.

On Ubuntu, compiler/simulator packages can be installed with:

```sh
sudo apt update
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf iverilog verilator build-essential python3-pip git curl
```

Keep Python dependencies isolated from the system environment:

```sh
python3 -m pip install --target "$HOME/.local/share/rv32-llm/python" --index-url https://download.pytorch.org/whl/cpu torch==2.14.1+cpu numpy==2.2.6
python3 -m pip install --target "$HOME/.local/share/rv32-llm/plot" matplotlib==3.10.9
```

The scripts discover these dependency directories automatically. An existing
environment with these modules also works. Version availability can differ on
other Python/platform combinations.

Reproduce the complete experiment:

```sh
python3 scripts/llm_reference.py
python3 scripts/llm_vectors.py
python3 scripts/llm_benchmark.py
python3 scripts/llm_benchmark.py --sim iverilog
python3 scripts/llm_failure_check.py
python3 scripts/llm_profile.py
python3 scripts/llm_report.py
```

For a small smoke test, add --quick to either benchmark invocation. Do not run
two benchmark processes concurrently: they deliberately share generated memory
images. Completed quick and full results use different filenames.

Stored real vectors allow RTL testing without PyTorch, network access, or the
checkpoint. Missing real.json means synthetic-only testing; the result rows
identify their source, and the summary states the case count.

## Host reference and model provenance

Upstream: https://github.com/karpathy/llama2.c
Pinned revision: 350e04fe35433e6d2941dce5a1f53308f87058eb.

The reference script obtains stories15M.pt from Karpathy's tinyllamas repository.
It verifies SHA-256 before loading the checkpoint:
3da00c0fef684f3f83b457736837c46ab55e92a26662b61d6104de2d271c708d.

It invokes the pinned upstream interface:

```sh
python3 export.py stories15M-q80.bin --version 2 --checkpoint stories15M.pt
```

The old floating-point stories15M.bin format is not used with runq.c.
The version-2 export has magic 0x616b3432 and a 256-byte header. The exported
model has dim=288, hidden_dim=768, six layers, six heads, vocabulary 32000,
and sequence length 256. Export backs the requested group size down from 64
to 32 because 288 is not divisible by 64.

Weights and activations each contain signed INT8 arrays and one float scale per
group. For each output row, runq.c computes exact integer group dot products,
multiplies each by that group's weight and activation scales, and adds the
scaled contributions in floating point. A whole-row integer sum cannot replace
this group-by-group scaling.

The extraction script creates an instrumented copy under build/llm_reference.
It calls the original matmul before reading its inputs and outputs. It captures
rows zero and one of first-layer query and FFN down projections at token positions
zero and one. Call selection is explicitly validated for the pinned six-layer
model; it is not a general mapping for arbitrary models.

Inference uses prompt "Once upon a time", greedy sampling, seed 1, and 16 steps.
Original and instrumented programs produce identical generated text.
Eight complete rows are captured; 56 real test cases include prefixes of 32,
64, 256, complete 288/768 rows, and all 24 groups of one complete FFN row.
Python calculates exact integer references and reconstructs the scaled outputs
with float32 rounding. Integer comparisons are exact; scaled-output checking
uses a small rounding tolerance.

The model's longest actual matmul input is 768. Real 1024-element rows do not
exist here; 1024 and 2048 tests are explicitly synthetic.

## Vector format

bench/llm/vectors/real.json contains:

- provenance: source revision, checkpoint and exported-model hashes, model
  configuration, prompt, group size, and instrumentation check;
- captures: full INT8 rows/activations, original matrix dimensions, row/call
  identifiers, scales, group integer results, actual and reconstructed outputs;
- vectors: directly runnable integer tests with a, b, expected, source, and
  source/group metadata.

synthetic.json records seed 20261102 and 25 deterministic cases: lengths
0, 1, 2, 3, 4, 5, 7, 15, 31, 32, 63, 64, 65, 127, 128, 255, 256, 257,
1024, 2048; zero vectors; signed extremes; ordered mixed lanes; and all pairs
from {-128,-1,0,1,127}. These cases are not claimed as LLM captures.

## C compilation and instruction wrappers

bench/llm/kernels.c has separate noinline scalar_dot and simd_dot functions.
Both are compiled with:

```text
-march=rv32i -mabi=ilp32 -mno-relax -msmall-data-limit=0
-ffixed-x31 -O2 -ffreestanding -fno-pic -fno-pie
-fno-stack-protector -fno-asynchronous-unwind-tables
```

Linking uses -nostdlib, --no-relax, and the benchmark linker script.
No compiler-generated full-M instructions are enabled or assumed.
The scalar baseline uses the existing single-cycle MUL explicitly:

```asm
.insn r 0x33, 0, 1, rd, rs1, rs2
```

DOT8 uses the verified custom-0 encoding:

```asm
.insn r 0x0b, 0, 0, rd, rs1, rs2
```

funct7=0, funct3=0; lane i is bits [8*i +: 8] interpreted as signed INT8.
Four products are summed exactly and sign-extended to 32 bits. There is no
internal accumulator; an ordinary ADD accumulates each partial sum.

Aligned inputs use inline LW loads without aliasing pointer casts. Equal
misalignments use scalar prefix elements until alignment. Differing alignments
use unsigned byte shifts/or to pack safely. Remaining elements use scalar MUL.
All tested complete vectors have at most 2048 elements, so the signed int32
accumulator cannot overflow even for -128 times -128.

The program reads externally loaded operands after compilation, uses noinline
functions and volatile instruction wrappers, and cannot precompute results.
The runner confirms MUL and DOT8 binary encodings. Disassembly is saved at
build/llm_bench/program.dis; older objdump displays DOT8 as a numeric word.
Dynamic operation counts must match N scalar MULs, or packed DOT8s plus the
computed prefix/tail MULs.

## Benchmark memory and completion

Instruction image: 640 bytes, within the unchanged 1 KiB instruction memory.
Data memory: 8192 bytes. `DMEM_BYTES` in scripts/llm_benchmark.py controls the
RTL capacity, full data-image length, and startup's compiled stack pointer.

| Data byte address | Meaning |
|---|---|
| 0 | Result store observed by the testbench |
| 16 | Complete vector length |
| 20 | Variant: 0 scalar, 1 DOT8 |
| 24 | First vector pointer |
| 28 | Second vector pointer |
| 128 + offset_a | First INT8 vector |
| base + 32 + offset_b | Second vector, shifted layout |
| base + offset_b | Second vector, deliberately conflicting layout |
| 7936-8191 | Reserved stack area; SP starts at 8192 |

Here `base = 128 + round_up(max(length, 256), 64)`. This prevents overlap
for complete vectors and preserves the two arrays' cache-index relationships.
For length 256 the original second-vector addresses 416/384 are unchanged.

Offsets (0,0), (1,1), and (1,2) exercise alignment paths on selected tests.
Runtime assertions in the image generator prevent vector overlap and stack
overlap. The benchmark main uses no static initialized/BSS data; the earlier
general C flow continues to verify those features separately.

Two invocations execute per reset. x31 is compiler-reserved and used as an
EX-stage marker: ADDI x31,x0,1 starts a window; ADDI x31,x0,2 ends it.
Each window must issue exactly one accepted result store. The observer checks
its forwarded store data when the pipeline advances, avoiding stale backing
memory when the D-cache holds dirty data. Completion is independent of the
expected result, with a 200000-cycle timeout.

## Measurement methodology

The cycle window runs from the advancing start marker in EX to the advancing
end marker. It includes argument setup, dispatch, call/return, result store,
pipeline redirects, load-use stalls, and cache stalls. It excludes startup and
host image loading. These small call/dispatch costs remain part of each reported
kernel window and explain overhead at short lengths.

Instruction counts are non-stalled EX-stage instructions, excluding bubbles and
both marker instructions. There is no architectural retired-instruction counter.
MUL/DOT8 counts, cache-held cycles, and load-use stalls are independently recorded.
Raw CSV includes cycles since reset; summary CSV includes first-window startup
overhead. The same binary, layout, inputs, latency, and reset conditions are used
for both variants.

Configurations:
1. Bypass caches/predictor; ideal memory (latency parameter ineffective).
2. Caches and predictor enabled; backing latency 1.
3. Caches and predictor enabled; backing latency 5.

First invocation starts after reset/startup, so startup has already accessed
some instructions, stack and control data. Repeated invocation retains cache
and predictor state; "repeat" does not mean the working set fits in cache.

Each entire input pair now fits in 8 KiB, including the 2048-element synthetic
vectors. Every measurement is one uninterrupted complete-vector kernel call;
there is no per-chunk reset, host accumulation, or sum of short timing windows.
Input loading remains outside the measured window. The earlier 1 KiB/chunked
results are retained under results/llm/legacy_1k/ as historical measurements.
They must not be mixed with the current complete-vector measurements.

## Findings

With 8 KiB data memory, a full real 768-element FFN row takes 7697 scalar cycles
versus 1962 DOT8 cycles in bypass mode (3.923x), and 9923 versus 5597 with caches
at latency 5 (1.773x). These are direct complete-row measurements, not chunk sums.
The full 2048-element synthetic case takes 20497 versus 5162 cycles in bypass
mode and 25923 versus 13917 in the same cached configuration.

For aligned 256-element inputs in the shifted layout, scalar takes 2577 cycles
and DOT8 682 cycles in bypass mode: 3.779x. EX instructions drop from 1804 to 481,
and multiply operations change from 256 MULs to 64 DOT8s.

With caches and backing latency 5, the same comparison is 3523 versus 2269 cycles:
1.553x. DOT8 spends 1709 of those cycles held by cache misses (instruction and data
combined), so reducing arithmetic alone no longer yields the near-fourfold bypass
improvement. Forwarding avoids many dependencies but load-use interlocks remain.

The aligned SIMD loop loads two words, computes DOT8, adds its result, advances
pointers and branches. One ADD is still needed per four products because DOT8
does not accumulate internally. Scalar loads signed bytes and multiplies one pair
per iteration. Packed loads reduce loop work and load-use events.

Cache layout matters. At length 256 and latency 5, placing arrays 256 bytes apart
maps their corresponding words to the same direct-mapped cache index: scalar
rises to 6979 cycles while DOT8 stays at 2269. Scalar repeatedly evicts/reloads the
same words while consuming individual bytes; DOT8 consumes each complete word.
This 3.076x conflict-case speedup must not be substituted for the shifted-layout
1.553x result without explaining the changed placement.

Misalignment has a cost: at length 64 with differing alignments, the bypass DOT8
path takes 467 cycles rather than the aligned path's 202. Small vectors can lose
to scalar due to setup/prefix/tail overhead. Raw tables retain these cases.

## Host profiling and limitations

scripts/llm_profile.py times original mathematical routines in a separate copy:
matmul, rmsnorm, softmax, quantize, and total forward. Three single-thread
128-step runs have identical generated text to the uninstrumented binary.
Median matmul fraction is about 96.56% of instrumented forward time. Timing uses
CLOCK_MONOTONIC and includes instrumentation/WSL scheduling effects.
The residual forward category combines attention dot/value loops, RoPE, nonlinear
activation loops, residual updates and remaining overhead. Those loops are not
separately profiled.

This host fraction is evidence of kernel relevance, not an end-to-end target
speedup prediction. Quantization, float scales, normalization, attention and
nonlinear operations still execute on the host. No FPU, full Transformer port,
new SIMD instruction, or model training was added.

No synthesis/area reports were found, so the area cost of DOT8 and the enlarged
RAM, and physical frequency, remain unmeasured. The simulation now has enough
memory to measure complete rows. A useful next step is a group-scaled row
interface that includes data movement and scaled accumulation costs.

## Files and reproducibility

| Files | Purpose |
|---|---|
| bench/llm/kernels.c, start.S, link.ld | Compiled scalar/SIMD C and startup |
| bench/llm/capture_hook.c | Read-only host input/output capture |
| bench/llm/vectors/*.json | Small real/synthetic test data and provenance |
| scripts/llm_reference.py | Pinned reference, quantization and extraction |
| scripts/llm_vectors.py | Deterministic vectors and exact references |
| scripts/llm_benchmark.py | Compilation, images, RTL tests and raw CSV |
| scripts/llm_profile.py | Separate host timing |
| scripts/llm_report.py | Cross-simulator comparison, summary and plots |
| scripts/llm_failure_check.py | Confirms wrong results are rejected in both simulators |
| sim/llm_bench_top.sv | Shared marker/counter/result observer |
| sim/tb_llm_bench.sv | Icarus clock/reset harness |
| sim/llm_bench_main.cpp | Verilator clock/reset harness |
| rtl/memory/data_mem.v, rtl/core/top.v | Configurable data-memory capacity/index width |
| results/llm/ | Measured CSV, summaries, plots, host profile |
| .gitignore | Excludes checkpoints, binaries and build products |

Upstream code remains in an ignored checkout with its MIT license; instrumentation
is reproducibly generated. The repository's pre-existing uncommitted changes
and file reorganization were preserved.
