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
- **tcllib** (`yaml` + `json`) — required only for the manifest features, and not
  uniformly:
  - `read_manifest` and `load_manifest` (reading canonical YAML manifests) run a
    pre-flight (`require_libs`) that **fails loudly with install guidance** when
    tcllib is absent, rather than degrading silently.
  - `collect_project_files` on YAML input runs that same pre-flight, but for `yaml`
    alone: it needs no `json`. Its other input formats need no tcllib.
  - `validate` runs that same pre-flight, but for `json` alone: it needs the
    schema reader, not YAML parsing. A missing `json` fails loudly with install
    guidance, matching the other manifest entry points.
  - `normalize` works on plain dicts and needs no tcllib.

The VHDL parser (`vhdlscan` and the `q_*` queries) needs **no tcllib** — it works on
the base Tcl interpreter. Likewise, `package require aurig::core` loads quietly with
or without tcllib present; the requirement only bites at the point a manifest is read
or validated.

The manifest features have been verified working with tcllib 1.20 (`yaml` 0.4.1,
`json` 1.3.4) and with tcllib 1.21 (`yaml` 0.4.2, `json` 1.3.6). Other tcllib
releases may work but have not been verified. This is the canonical statement of
the verified environments; [CONTRIBUTING.md](CONTRIBUTING.md#running-the-test-suite)
refers back to it rather than repeating the figures.

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
vendor tool), and the one that `tclsh` on `PATH` resolves to is not always the one you
expect. The second line must report 8.5 or later.

**Step 2 — only if you use manifests** (`read_manifest`, `load_manifest`,
`collect_project_files` on YAML input, or `validate`):

```tcl
puts [package require yaml]
puts [package require json]
```

Each line prints the tcllib package version if it is found. If step 2 raises an error
and you only use the VHDL parser and queries, that is fine — nothing is missing for your
use.

### FPGA vendor tools ship their own Tcl

Vivado, Quartus and Diamond each bundle a Tcl interpreter, and their installers can put
it on `PATH`. That interpreter does not necessarily match the versions above: Vivado
2023.1, for instance, ships Tcl 8.5 with tcllib 1.11, an older tcllib than any this
project has been verified with. Run step 1 to see which interpreter you actually get
before assuming the bundled one is the one in use.

### Obtaining Tcl on Windows

The verification snippet above checks the prerequisites; passing it does not by itself
prove the project runs successfully on a given distribution. Ways to obtain a Tcl, in
no particular order, each with its own friction:

- **ActiveTcl** — requires a free ActiveState account; the free tier limits the number
  of runtimes executed per 24 hours.
- **Magicsplat Tcl/Tk** — `winget install Magicsplat.TclTk`; no account. This project
  has **not** been tested with Magicsplat. Its installer major version 1 is Tcl 8.6;
  major version 2 is Tcl 9.0, and nothing here has been tried against Tcl 9 at all.
- **An existing Tcl** that already passes the verification above — nothing to install.

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
