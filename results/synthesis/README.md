# Artix-7 synthesis results

Vivado 2025.2 synthesized the cached CPU with DOT8 and 8 KiB of data memory
for xc7a100tcsg324-1 in out-of-context mode. The synthesis harness adds a
programmable instruction memory port and observes PC, register writeback,
and stores. Both caches and branch prediction were enabled.

| Resource | Used | Device capacity | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 25,604 | 63,400 | 40.38% |
| Flip-flops | 74,015 | 126,800 | 58.37% |
| DSPs | 3 | 240 | 1.25% |
| Block RAM tiles | 0 | 135 | 0% |

The data-memory module accounts for 21,011 LUTs and 66,753 flip-flops.
Vivado expanded the 8 KiB array into registers because of the asynchronous
reset process around its writes. Under the DOT8 hierarchy, Vivado reports
88 LUTs, zero flip-flops, and zero DSPs. Hierarchical attribution does not
include the full instruction's effect on surrounding decode and mux logic.

At the 100 MHz constraint (10 ns period), post-synthesis worst setup slack
was -6.535 ns and worst hold slack was +0.156 ns. The worst reported setup
path runs from the MEM/WB write-enable register to the ID/EX clock enable.
These figures are pre-route estimates. This report covers the DOT8 configuration.

- [Utilization](dot8/synth_utilization.rpt)
- [Hierarchical utilization](dot8/synth_hierarchy.rpt)
- [Timing](dot8/synth_timing.rpt)
- [Design rule checks](dot8/synth_drc.rpt)