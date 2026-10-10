<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# AURIG Core

> **AURIG Core** is part of the [AURIG stack](https://github.com/aurig-fpga) — open-source FPGA tooling by [LogiMentor](https://logimentor.com).
>
> See also: [Sentinel](https://github.com/aurig-fpga/aurig-sentinel) · [Build](https://github.com/aurig-fpga/aurig-build) · [Lint](https://github.com/aurig-fpga/aurig-lint) · [Doc](https://github.com/aurig-fpga/aurig-doc)

The shared Tcl library underneath the AURIG VHDL tooling: a VHDL parser that turns
source into a structured, queryable dictionary; YAML/INI and project-file utilities;
and the canonical AURIG project-manifest schema (normalize + validate). It is the
common dependency of [AURIG Lint](https://github.com/aurig-fpga/aurig-lint) and
[AURIG Doc](https://github.com/aurig-fpga/aurig-doc) and is rarely used on its own — but it
is a fully standalone package you can drive directly.

## What's inside

Everything lives under the `aurig::core` package, in three sub-namespaces:

- **`::aurig::core::analyze`** — the VHDL parser. `vhdlscan` reads a `.vhd`/`.vhdl`
  file into a structured parse dictionary; a family of `q_*` query helpers
  (`q_entity_names`, `q_entity_ports`, `q_entity_generics`, `q_libraries`, `q_uses`,
  `q_architectures`, `q_arch_instantiations`, `q_arch_signals`, `q_packages`, …)
  read structured information back out without manual dict traversal.
- **`::aurig::core::util`** — I/O and project utilities: `readYaml`/`writeYaml`,
  `readIni`/`writeIni`, `ini2yaml`/`yaml2ini`, path resolution, and
  `collect_project_files` (resolves a manifest's `file_sets` globs into a file list).
- **`::aurig::core::schema`** — the canonical AURIG project manifest: `normalize`,
  `validate`, and `load_manifest`/`scan_project`, checked against the JSON Schema
  vendored in-tree at [`schema/manifest-v1.json`](schema/manifest-v1.json).

## Requirements

- **Tcl 8.5+** (8.6 recommended; CI runs 8.6).
- **tcllib** (`yaml` + `json`) — required only for the manifest features and for
  `readYaml`, and not uniformly:
  - `read_manifest` and `load_manifest` (reading canonical YAML manifests) run a
    pre-flight (`require_libs`) that **fails loudly with install guidance** when
    tcllib is absent, rather than degrading silently.
  - `collect_project_files` on YAML input runs that same pre-flight, but for `yaml`
    alone: it needs no `json`. Its other input formats need no tcllib.
  - `validate` runs that same pre-flight, but for `json` alone: it needs the
    schema reader, not YAML parsing. A missing `json` fails loudly with install
    guidance, matching the other manifest entry points.
  - `yaml2ini` (converting a canonical YAML manifest to INI) gates on tcllib
    `yaml` alone via its own two-branch guard, matching `collect_project_files`
    on YAML input.
  - `readYaml` requires tcllib `yaml` for ANY input, not only canonical manifests:
    it has no lite-parser fallback, and calling it without tcllib fails loudly
    with install guidance rather than returning a mis-parsed dict.
  - `normalize` works on plain dicts and needs no tcllib.

The VHDL parser (`vhdlscan` and the `q_*` queries) needs **no tcllib** — it works on
the base Tcl interpreter. Likewise, `package require aurig::core` loads quietly with
or without tcllib present; the requirement only bites at the point a manifest is read
or validated, or `readYaml` is called on any input.

The manifest features have been verified working with the tcllib releases below. In
each case the test suite passed, and the `yaml`/`json` versions are the ones that
each interpreter reported:

| tcllib | `yaml` | `json` | Verified on |
| ------ | ------ | ------ | ----------- |
| 1.20 | 0.4.1 | 1.3.4 | ActiveTcl 8.6.14, Windows |
| 1.21 (Ubuntu package `1.21+dfsg-1`) | 0.4.1 | 1.3.4 | Tcl 8.6.14, `ubuntu-latest`; the CI test job |
| 2.0 | 0.4.2 | 1.3.6 | Magicsplat 1.16.0 (Tcl 8.6.16), `windows-latest`; one-off CI run |

Other tcllib releases may work but have not been verified. This is the canonical
statement of the verified environments;
[CONTRIBUTING.md](CONTRIBUTING.md#running-the-test-suite) refers back to it rather
than repeating the figures.

### Verify your interpreter

This is the single criterion for "is my Tcl good enough". Run the two steps in a
`tclsh` session (or pipe them into `tclsh`).

**Step 1 — always:**

```tcl
puts [info nameofexecutable]
puts [info patchlevel]
```

The first line tells you *which* Tcl you are actually running. A machine may carry
more than one Tcl (system package, a standalone distribution, one bundled with an FPGA
vendor tool, the one Git for Windows ships for its own use), and the one that `tclsh`
on `PATH` resolves to depends on the shell you start it from and is not always the one
you expect. The second line must report 8.5 or later.

**Step 2 — only if you use manifest features or read YAML directly.** Which
tcllib package you need depends on the entry point (see the bullets above):
`read_manifest`, `load_manifest`, `collect_project_files` on YAML input,
`yaml2ini`, and `readYaml` need `yaml`; `read_manifest`, `load_manifest`, and
`validate` need `json`. Run whichever apply:

```tcl
puts [package require yaml]   ;# reading canonical YAML manifests or readYaml
puts [package require json]   ;# schema validation
```

Each line prints the tcllib package version if it is found. If step 2 raises an error
and you only use the VHDL parser and queries, that is fine — nothing is missing for your
use.

**If the check fails or names an unexpected interpreter:**

- Step 1 names a Tcl you did not mean to run: the problem is *which* Tcl starts, not
  what is installed. Do not install anything yet; see
  [Another Tcl first on `PATH`](#another-tcl-first-on-path).
- Step 1 names the Tcl you meant, but the version is below 8.5: that interpreter does
  not meet the requirements, and adding packages cannot change its version. Use a
  different Tcl (on Windows, see
  [Getting a Tcl on Windows](#getting-a-tcl-on-windows)), then run the check again.
- Step 1 names the Tcl you meant and the version is fine, but step 2 fails for a
  package you need: add tcllib to that interpreter, or use a different Tcl (on
  Windows, see [Getting a Tcl on Windows](#getting-a-tcl-on-windows)), then run the
  check again.

### Another Tcl first on `PATH`

A machine can hold a complete Tcl and still fail the check, because another Tcl on
the machine, such as the one Git for Windows ships or one bundled with an FPGA vendor
tool, comes first on `PATH`.

**Git Bash on Windows.** Git for Windows ships its own Tcl at
`C:/Program Files/Git/mingw64/bin/tclsh.exe` for Git's own tools, with **no tcllib**.
Git Bash puts `/mingw64/bin` first on `PATH`, so a bare `tclsh` in a Git Bash window is
that interpreter, even on a machine that also has a complete Tcl. This has been
reproduced on a machine with a working ActiveTcl and tcllib: from Git Bash,
`which tclsh` gives `/mingw64/bin/tclsh` and `package require yaml` fails with
`can't find package yaml`, while from PowerShell the same machine passes the check. It
also happened on a GitHub Actions `windows-latest` runner.

In that state the aurig-core error tells you to install tcllib — while tcllib is
already installed. That is why step 1 prints `info nameofexecutable` first. If it reports
`C:/Program Files/Git/mingw64/bin/tclsh.exe`, do not install anything: run the Tcl you
intended by its full path, or work from PowerShell. Both have been verified to work.

**FPGA vendor tools.** Vivado, Quartus and Diamond each bundle a Tcl interpreter, and
their installers can put it on `PATH`. That interpreter does not necessarily match the
verified tcllib table above: Vivado 2023.1, for instance, ships Tcl 8.5 with tcllib 1.11, an older
tcllib than any this project has been verified with. Run step 1 to see which
interpreter you actually get before assuming the bundled one is the one in use.

### Getting a Tcl on Windows

Only needed if no Tcl on the machine passes the check. The check is the criterion; the
entries below are examples, not recommendations, each marked with what has and has not
been verified. Passing the check confirms the prerequisites; the full test suite has
been run only on the environments in the verified tcllib table above.

- **An existing Tcl that passes the check** — nothing to install.
- **Magicsplat Tcl/Tk 1.16.0 — verified.** The full CI test suite passed on it in a
  one-off run on a GitHub Actions `windows-latest` runner, installed non-interactively
  with no prompts:

  ```powershell
  choco install magicsplat-tcl-tk --version 1.16.0 -y
  ```

  It provides Tcl 8.6.16 and tcllib 2.0 (`yaml` 0.4.2, `json` 1.3.6). Keep the
  `--version` pin. Magicsplat's installer major version 1 is Tcl 8.6 and major version
  2 is Tcl 9.0; the Chocolatey package now tracks the 2.x line, so an unpinned install
  gives Tcl 9.0, which nothing here has been tried against. Chocolatey is not part of a
  stock Windows installation (it was absent on the developer machine checked), so this
  route needs Chocolatey installed first. Not tested: later 8.6-based Magicsplat
  releases such as 1.18.0, installing Magicsplat's MSI directly, and the package's
  32-bit installer (Chocolatey selected the 64-bit one).
- **The "last free download" ActiveTcl 8.6.14 build — not verified.** A build
  published at `platform.activestate.com/ActiveState/ActiveTcl-8.6`, labelled "Last
  free download of Tcl from ActiveState", downloads without signing in. It is a fork
  project frozen at Tcl 8.6.14, not a maintained channel; current ActiveState
  distribution goes through their platform rather than a plain download. Whether that
  build includes tcllib, and whether it matches the ActiveTcl 8.6.14 in the verified
  table, has not been checked — run step 2 after installing it.

## Quick start (standalone)

```tcl
# Put the core checkout on the package path, then require it.
lappend ::auto_path /path/to/core
package require aurig::core

# Parse a VHDL file into a structured dictionary.
if {[catch {
    set ast [::aurig::core::analyze::vhdlscan -in design.vhd]
} err options]} {
    puts stderr $err
    puts stderr [dict get $options -errorcode]
    return
}

# Query it.
foreach e [::aurig::core::analyze::q_entity_names $ast] {
    puts "entity: $e"
    foreach p [::aurig::core::analyze::q_entity_ports $ast $e] {
        puts "  port [dict get $p name] : [dict get $p mode] [dict get $p type]"
    }
}
```

Working with a canonical project manifest (this path **requires tcllib**):

```tcl
package require aurig::core
package require yaml   ;# tcllib; require_libs will demand it otherwise

# Read + normalize + validate against the vendored schema. load_manifest runs the
# full pipeline and returns a {normalized-config warnings} pair.
lassign [::aurig::core::schema::load_manifest project.yaml] cfg warnings

# Expand the manifest's file_sets into concrete source files.
set files [::aurig::core::util::collect_project_files -from project.yaml -format yaml]
```

## Using AURIG Core as a dependency

AURIG Core is a **library**, not a CLI: consumers put its checkout on the Tcl package
path and `package require aurig::core`. The dev/CI knob is the native `TCLLIBPATH`
environment variable (a Tcl list of dirs prepended to `::auto_path`):

```sh
TCLLIBPATH='/path/to/core' tclsh your_tool.tcl
```

This is exactly how AURIG Lint and AURIG Doc resolve their parser/util/schema layer —
they vendor no copy of it and declare `package require aurig::core` at the top of each
file that uses it. On Windows, use forward slashes in `TCLLIBPATH`.

## The manifest schema

`schema/manifest-v1.json` is the canonical AURIG project-manifest contract, vendored
in-tree (no runtime URL resolution). Core's validator is **lenient**: it normalizes
and accepts any input a valid manifest could take and never false-rejects valid
manifests; the authoritative strict validator is [AURIG Build](https://github.com/aurig-fpga/aurig-build).
AURIG Build is the authoritative reference for any strict-vs-lenient divergence.

## Development

```sh
git clone https://github.com/aurig-fpga/aurig-core.git
cd aurig-core
```

Installing Tcl + tcllib for development and running the test suite (parser harnesses,
schema, project-file resolution) are covered in
[CONTRIBUTING.md](CONTRIBUTING.md#running-the-test-suite).

The parser is covered by an extensive fixture corpus under `test/parser/`
(VHDL source + expected parse output). `test/test_core_isolation.tcl` proves the
package resolves entirely from its own repo with no hidden dependency, and
`test/test_schema_tcllib_absent.tcl` proves the loud-failure path when tcllib is
unavailable. CI (`.github/workflows/ci.yml`) runs the gated subset on Tcl 8.6.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Copyright 2024-2026 LogiMentor S.r.l.
