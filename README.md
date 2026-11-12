# RV32 processor with DOT8

A five-stage pipelined processor implementing a subset of RV32I, scalar `MUL`, and a custom `DOT8` instruction that sums four signed INT8 products. Use `rtl/files.f` from the repository root to compile `top`.

Run the quantized LLM kernel benchmark with `python3 scripts/llm_benchmark.py`. See the [reproduction guide](docs/llm-benchmark.md) for dependencies and the [benchmark results](results/llm/README.md) for measured cycle counts.
