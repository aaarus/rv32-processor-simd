#include "Vllm_bench_top.h"
#include "verilated.h"

#include <iostream>

static double simulation_time = 0;

double sc_time_stamp() {
    return simulation_time;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vllm_bench_top cpu;

    auto tick = [&]() {
        cpu.clk = 0;
        cpu.eval();
        simulation_time += 5;
        cpu.clk = 1;
        cpu.eval();
        simulation_time += 5;
        cpu.clk = 0;
        cpu.eval();
    };

    cpu.rst = 1;
    for (int i = 0; i < 3; ++i)
        tick();

    cpu.rst = 0;
    for (int i = 0; i < 200001 && !cpu.done; ++i)
        tick();

    const bool passed = cpu.done;
    cpu.final();
    if (!passed) {
        std::cerr << "Timeout\n";
        return 1;
    }

    std::cout << "PASS llm benchmark\n";
}
