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
- **tcllib** (`yaml` + `json`) — required only for the manifest features: reading
  canonical YAML manifests and running schema `validate`/`normalize`. These call a
  pre-flight (`require_libs`) that **fails loudly with install guidance** when tcllib
  is absent, rather than degrading silently.

The VHDL parser (`vhdlscan` and the `q_*` queries) needs **no tcllib** — it works on
the base Tcl interpreter. Likewise, `package require aurig::core` loads quietly with
or without tcllib present; the requirement only bites at the point a manifest is read
or validated.

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

# Tcl 8.6 + tcllib (Debian/Ubuntu)
sudo apt-get install -y tcl tcllib

# Run the test suite (parser harnesses, schema, project-file resolution).
for t in test/test_*.tcl test/parser/run_doc.tcl; do tclsh "$t"; done
```

The parser is covered by an extensive fixture corpus under `test/parser/`
(VHDL source + expected parse output). `test/test_core_isolation.tcl` proves the
package resolves entirely from its own repo with no hidden dependency, and
`test/test_schema_tcllib_absent.tcl` proves the loud-failure path when tcllib is
unavailable. CI (`.github/workflows/ci.yml`) runs the gated subset on Tcl 8.6.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Copyright 2024-2026 LogiMentor S.r.l.
