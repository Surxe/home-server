---
name: wrf-export
description: The WRF game-data export (WRFrontiersDB-CUE4Parse, run by the Exporter) - its memory cap, exit codes, phases, and where its Linux natives come from
metadata:
  type: reference
---

The patch-day export is **WRFrontiersDB-CUE4Parse** (`/srv/dev/repos/WRFrontiersDB-CUE4Parse`,
replaced CUE4P-BatchExport in 2026-10, v2.0.0). The Exporter downloads its zip release into
`WRFrontiers-Exporter/src/batch_export/WRFrontiersDB-CUE4Parse/` and runs it with three
path flags. One process exports assets, then meshes, then maps (into
`exports/<version>/map-export`, which the Parser cooks), then config.

- **Memory cap:** Exporter option `BATCH_EXPORT_MEMORY_MAX` (default `1536M`, forwarded by
  the Orchestrator). On Linux the export runs in a `systemd-run --user --scope` with
  `MemoryMax` and no swap; .NET takes 75% of it as its GC heap limit, and the tool sizes
  its workers from that budget (constants in `src/WrfConstants.cs`). It leaves room for
  Valheim (VM 100). 768M also worked on 2026-10-17, so the default is conservative.
- **Exit codes:** `0` ok; `1` export failures (the tool prints a per-phase summary);
  `3` .NET out of memory; `137` (Python `-9`) killed by the cgroup OOM killer when native
  memory overran the cap first. For 3 or 137, raise the cap. The Exporter's
  `describe_exit` explains each one in its error.
- **Linux natives:** the release is self-contained. CI runs `scripts/fetch-linux-natives.sh`,
  which fetches Oodle and libSkiaSharp (pinned sha256) and builds `libdetex.so` from a
  pinned hglm/detex commit, all placed next to the executable. CUE4Parse's own Detex is a
  Windows DLL. If PNGs or meshes go missing on Linux, check those three files first.
  Windows downloads Oodle at run time instead.
- **Timing (box, v2.0.0):** about 8.5 min (assets 1:17, meshes 4:30, maps 2:35).
