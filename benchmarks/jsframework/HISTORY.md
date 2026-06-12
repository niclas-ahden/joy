# Joy performance history (js-framework-benchmark)

Each row is one full run. Lower is better; "slowdown" is the geomean factor vs the
fastest framework on each CPU benchmark. See `runs/<timestamp>/report.md` (local,
not tracked) for the full cross-framework table of that run.

| run | Joy commit | percy commit | CPU geomean (ms) | slowdown vs best | memory (MB) | bundle (KB) |
|---|---|---|---|---|---|---|
| 2026-06-11 23:16 CEST<sup>1</sup> | `41a3f71` | `4641663c` | 60.8 | 2.73× | 4.8 | 81.8 |

<sup>1</sup> Quiet machine, FULL run. The geomean includes 07_create10k (641.5 ms, measured unbatched) for all frameworks. The size-prefix allocator and the size-tuned release profile (opt-level=z, LTO, wasm-opt -Oz) cost nothing measurable on CPU, and the bundle is 81.8 KB.
