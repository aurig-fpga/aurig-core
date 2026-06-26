<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# Changelog

All notable changes to aurig-core are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-22

Initial public release of aurig-core as part of the AURIG open-source FPGA
tooling stack.

### Added

- VHDL parser (`::aurig::core::analyze::vhdlscan`) that reads source into a
  structured parse dictionary, with a family of `q_*` query helpers
  (`q_entity_names`, `q_entity_ports`, `q_libraries`, `q_packages`, …).
- YAML/INI and project-file utilities (`::aurig::core::util`): `readYaml`/
  `writeYaml`, `readIni`/`writeIni`, `ini2yaml`/`yaml2ini`, path resolution, and
  `collect_project_files`.
- Canonical AURIG project-manifest schema (`::aurig::core::schema`): `normalize`,
  `validate`, and `load_manifest`/`scan_project`, checked against the JSON Schema
  vendored in-tree at `schema/manifest-v1.json` with an in-tree SHA-256 drift
  guard.

### Changed

- Carved from the legacy `tcl4fpga` monolith into a standalone, CLI-less library.
- Tcl namespace and package cutover to the AURIG namespace: the package is now
  `aurig::core` and procs live under `::aurig::core::{analyze,util,schema}`.
  Direct cutover, no compatibility alias.

### Dependencies

- **Tcl 8.5+**. **tcllib** (`yaml` + `json`) is required only for the manifest
  features; the parser and queries run on the base interpreter.

### License

- Released under the Apache License 2.0.

[Unreleased]: https://github.com/aurig-fpga/aurig-core/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/aurig-fpga/aurig-core/releases/tag/v0.1.0
