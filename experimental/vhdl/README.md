# Experimental VHDL structural frontend

This opt-in Tcl frontend explores a source-preserving structural index for VHDL. It retains normalized source, a token tape, source spans, syntactic owners and explicit coverage evidence. The current experimental reference is c7f40b8e705c475dfbd7afb3cc122016ccddd6d4. The authoritative Core command remains ::aurig::core::analyze::vhdlscan. Treat the experimental commands, result dictionaries, and identifiers as private and revision-specific.

## Opt in

Use a fresh Tcl interpreter with a checked-out Core directory. Source the experimental entry point explicitly, then load the production source reader. Use an explicit VHDL edition of 1993, 2002, or 2008.

~~~tcl
set core [file normalize {/path/to/aurig-core}]
source [file join $core experimental vhdl frontend.tcl]
::vhdl_index::load_reader [file join $core util vhdl_source.tcl]
set index [::vhdl_index::analyze_file [file join $core test experimental fixtures groups.vhd.fixture] 2008]
set view [::vhdl_index::regions::view $index]
puts [::vhdl_index::query::units $view]
~~~

The frontend requires explicit opt-in. Core loads its production parser by default. Tcl 8.5.19 and 8.6.14 are the Linux reference runtimes. The frontend uses Tcl and the existing Core reader without needing a VHDL compiler or vendor license.

## Structural profile

Structural extraction is limited to declaration and envelope boundaries. The profile includes design-unit and context boundaries, supported entity and component interfaces, ordinary object declarations, subtypes and scalar and composite type declarations, physical/access/file types, and protected and subprogram envelopes in supported regions. It also indexes selected alias, attribute, file-object, group, disconnect, configuration-specification and local-use structures. Edition and owner restrictions apply to each production.

Owner regions distinguish empty, partial, unsupported, withdrawn, and uncertain inventory. Queries return boundary availability, completeness for the requested family, grammar-validation status, and evidence with source spans. A proved empty direct inventory is distinct from an unavailable one. File-wide summaries remain conservative when a sibling or descendant is missing. Positions use normalized Tcl string offsets, one-based line numbers, and zero-based columns. Snapshot-local occurrence identifiers are qualified by role and snapshot.

Nested package contents, block and generate-alternative ownership, and configuration-block interiors remain outside the complete extraction profile. Concurrent and sequential bodies and expression payloads can have proved fences while their internals remain opaque. Semantic binding, type resolution and elaboration are outside this structural index. VHDL-2019 is unsupported.

## Run an experiment

From the repository root, select an explicit Tcl interpreter and a scratch directory outside the checkout.

~~~bash
runtime=/path/to/tclsh
scratch=$(mktemp -d)
env -u AURIG_EXPERIMENTAL_FRONTEND AURIG_EXPERIMENTAL_SCRATCH="$scratch" \
    "$runtime" test/experimental/private_queries.tcl
~~~

The focused repository-contained tests include candidate families, selected-name policy, owner regions, private queries, and declaration-family fixtures. Experimental source fixtures use the .vhd.fixture suffix. Some inherited whole-corpus differential and resource harnesses also need review archives and corpora kept separately from the Git branch. Record which tests and interpreter builds were used. Use the coordinator's qualification kit for native Windows smoke on the exact reviewed revision.

## Qualification at the experimental reference

| Environment | Result |
| --- | --- |
| Linux Tcl 8.5.19 and 8.6.14 | Full inherited experimental functional regression passed on both. The locked Core, Lint and Doc regressions also passed on the reviewed revision. |
| Native Windows ActiveTcl 8.6.14, AMD64 | Passed the exact-source smoke with 13 assertions. |
| Native Windows Tcl 8.5 | NOT RUN. The overall Windows verifier recorded NOT RUN because the second runtime was unavailable. The coordinator accepted the 8.6.14 result for the proposed experimental publication. |
| Vivado 2024.1 embedded Tcl 8.6.13 | Batch smoke passed. |
| Questa 2024.3 Tcl | Verification unavailable in the isolated environment because a license could not be checked out. |
| GitHub Actions | Hosted CI has not yet run. |

The qualification covers the experimental reference and the checks listed above. The query interface, result dictionaries, and source identities can change between revisions. Use Core's production vhdlscan for production consumers.
