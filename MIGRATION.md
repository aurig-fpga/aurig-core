<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# aurig-core — migration notes

## What this repository is

`aurig-core` is a **snapshot carve** of the lean, shared *core* of the
[tcl4fpga](https://github.com/LogiMentor/tcl4fpga) toolkit: the parser and
utility closure that the lint, doc, and project-analysis layers all build on.
It contains exactly the dependency closure of `core.tcl`:

- `core.tcl` (package entry point)
- `analyze/{schema,queries,parser_utils,vhdlscan}.tcl`
- `util/{common,vhdl_re,ini_yaml,project_files}.tcl`
- `schema/manifest.tcl` + `schema/manifest-v1.json` (project-manifest schema
  infrastructure: load + normalize + validate, and the parser-class consumer
  `::aurig::core::schema::scan_project`). The JSON contract is vendored
  byte-identical from aurig-build; see the header of `schema/manifest.tcl`
  for the manual cross-repo parity gate and the in-tree SHA-256 drift guard.

It deliberately does **not** include the leaf tools (`scan_project`,
`create_ini_file`, `project`, `power_rename`, the `vhdlscan_reports`
siblings), nor the lint engine, the documentation generator, the umbrella
(`init.tcl`), or the project bootstrap (`bootstrap_root.tcl`). aurig-core is a
CLI-less library: consumers load it with `package require aurig::core`.

## Package name

This repository provides `aurig::core`, renamed from the upstream
`tcl4fpga::core`. The rename to the `::aurig::core` namespace was a direct
cutover: there are **no** backward-compatibility aliases, since aurig-core has
no existing consumers (lint and doc are renamed in lockstep).

## History

This is a content snapshot, not a history-preserving filter. The full commit
history of these files lives in the upstream `tcl4fpga` repository. Treat the
upstream tree as the source of record for provenance; changes here will diverge
from that point forward.

## Tests

- `test/test_core_isolation.tcl` is the **carve proof**: in a child interpreter
  whose `auto_path` is restricted to this repo plus the system/tcllib entries
  (every tcl4fpga-tree entry stripped), it records every file sourced while
  `package require aurig::core` loads and asserts they all live under this
  repository — proving the core resolves with no reach into any tcl4fpga tree.
- The remaining `test/test_*.tcl` are the subset of the upstream suite that
  exercises only the core closure. Each was re-anchored to load via
  `package require aurig::core` (no `init.tcl` / `setup.tcl` /
  `helpers_root.tcl` / `bootstrap_root.tcl`).
