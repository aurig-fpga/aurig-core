<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# Contributing to aurig-core

Thanks for your interest in improving **aurig-core**, the shared Tcl library at
the base of the AURIG open-source FPGA tooling stack.

## What aurig-core is

`aurig-core` is a CLI-less library with three parts:

- a VHDL parser that turns source into a structured, queryable dictionary
  (`::aurig::core::analyze`);
- YAML/INI and project-file utilities (`::aurig::core::util`);
- the canonical AURIG project-manifest schema — normalize + validate
  (`::aurig::core::schema`).

It is the common dependency of the other AURIG tools (the lint engine and the
documentation generator), which load `aurig::core` off Tcl's `::auto_path` at
runtime. `aurig-core` itself depends on no other AURIG repository.

## Prerequisites

- **Tcl 8.5+** (8.6 recommended; CI runs 8.6).
- **tcllib** (`yaml` + `json`) — required only for the manifest features
  (reading canonical YAML manifests and running schema `validate`/`normalize`).
  The VHDL parser and the `q_*` queries need no tcllib.

## Running the test suite

`aurig-core` is standalone: the tests put the checkout on `::auto_path`
themselves, so you run them directly.

```sh
# Tcl 8.6 + tcllib (Debian/Ubuntu)
sudo apt-get install -y tcl tcllib

# Run every test plus the parser doc-profile harness
for t in test/test_*.tcl test/parser/run_doc.tcl; do tclsh "$t" || break; done
```

The schema harnesses (`test/test_schema_*.tcl`) require tcllib; without it they
fail loudly with install guidance rather than degrading silently. Each test
exits non-zero on failure, so the exit code is the source of truth.

On **Windows**, use forward-slash paths even though the drive uses backslashes
elsewhere.

## How to contribute

- Open one pull request per concern, based on `main`.
- Keep changes focused: small, single-purpose PRs.
- Files use **LF** line endings; do not introduce CRLF or a UTF-8 BOM.
- New `.tcl` source and project-authored docs carry the SPDX/copyright header
  used throughout the repo. Match the surrounding style.
- If you add or change behavior, add or update a `test/test_*.tcl` so it runs in
  CI (the CI test list lives in `.github/workflows/ci.yml`).

## License

By contributing, you agree that your contributions are licensed under the
Apache License 2.0 (see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE)).
