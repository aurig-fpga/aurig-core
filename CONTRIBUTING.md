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

The Tcl and tcllib requirement, and the snippet to verify which interpreter you are
running, live in the README under [Requirements](README.md#requirements). They are
not repeated here.

In addition, for development only:

- **tcllib `sha256`** — needed by the optional checksum guard
  (`::aurig::core::schema::verify_schema_checksum`, exercised by
  `test/test_schema_drift.tcl` and `test/test_schema_manifest.tcl`). Not needed for
  package loading, parsing, or ordinary manifest processing.

## Running the test suite

`aurig-core` is standalone: every test puts the checkout on `::auto_path` itself,
so you run the scripts directly from the repository root. No `TCLLIBPATH` is needed
(CI sets none).

Install Tcl + tcllib. On Debian/Ubuntu:

```sh
sudo apt-get install -y tcl tcllib
```

POSIX shell (Linux, WSL, Git Bash):

```sh
for t in test/test_*.tcl test/parser/run_doc.tcl; do tclsh "$t" || break; done
```

PowerShell:

```powershell
foreach ($t in (Get-ChildItem test/test_*.tcl) + (Get-Item test/parser/run_doc.tcl)) {
  tclsh $t.FullName
  if ($LASTEXITCODE -ne 0) { break }
}
```

These loops are interactive examples: each script exits non-zero on failure, so the
exit code is the source of truth and the loop stops at the first failing script.

The full suite passes on both Linux/WSL and Windows PowerShell. Under PowerShell it
has been run with ActiveTcl 8.6.14 and tcllib 1.20, one of the environments listed
under [Requirements in the README](README.md#requirements). Some test output uses
UTF-8 symbols that may render as mojibake under the default PowerShell code page;
this is cosmetic and not a failure.

The positive schema harnesses (`test/test_schema_manifest.tcl`,
`test/test_schema_drift.tcl`) require tcllib and exit non-zero without it. The
exception is `test/test_schema_tcllib_absent.tcl`, which deliberately hides tcllib
from a child interpreter and expects the guided failure.

CI (`.github/workflows/ci.yml`) runs on `ubuntu-latest`, installs Tcl and tcllib with
the same apt command shown above, and prints `info patchlevel` before running the
gated test list.

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
