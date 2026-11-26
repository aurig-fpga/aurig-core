# Experimental VHDL structural frontend

This opt-in Tcl frontend explores a source-preserving structural index for VHDL. It retains normalized source, a token tape, source spans, syntactic owners and explicit coverage evidence. The authoritative Core command remains ::aurig::core::analyze::vhdlscan. Treat the experimental commands, result dictionaries, and identifiers as private and revision-specific.

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

Structural extraction covers selected declaration, statement and expression-envelope boundaries. The profile includes design-unit and context boundaries, supported entity and component interfaces, ordinary object declarations, subtypes and scalar and composite type declarations, physical/access/file types, and protected and subprogram envelopes in supported regions. It also indexes selected alias, attribute, file-object, group, disconnect, configuration-specification and local-use structures. Edition and owner restrictions apply to each production.

Owner regions distinguish empty, partial, unsupported, withdrawn, and uncertain inventory. Queries return boundary availability, completeness for the requested family, grammar-validation status, and evidence with source spans. A proved empty direct inventory is distinct from an unavailable one. File-wide summaries remain conservative when a sibling or descendant is missing. Positions use normalized Tcl string offsets, one-based line numbers, and zero-based columns. Snapshot-local occurrence identifiers are qualified by role and snapshot.

Nested package declarations and bodies own their local declarations in supported VHDL-2008 contexts. Generic package headers retain formal clauses and structurally indexed maps. Package instantiations retain the referenced name and optional map without expanding exports. A nested package has its own source occurrence and remains outside the design-unit inventory.

Block statements own formal generic and port interfaces, local declarations and nested structural scopes. Guards and association expression interiors are opaque. For and if generate bodies support local declarations and optional declarative prefixes in VHDL-1993, 2002 and 2008. VHDL-2008 adds elsif and else alternatives, case generate, alternative labels and optional local endings. Each if or case alternative has a distinct owner. A for generate parameter has its own syntactic role. Ranges, condition and selector expressions, and case choices retain spans and selected structural fields.

The frontend retains explicit component, entity and configuration instantiations and implicit component forms with a map aspect. Targets use selected-name syntax, and direct entity instantiations may specify an architecture identifier. A labeled bare selected name contributes ambiguity evidence for component instantiation and concurrent procedure call. Instantiation inventories are direct or subtree queries using the private `instantiations` capability. One occurrence in a generate body is counted once. Entity statement parts do not admit instantiations.

The private `map_associations` capability exposes source-ordered positional and named elements in generic and port maps. Supported sites include concurrent instantiations, package and subprogram headers and instantiations where admitted, block headers, formal package generic maps, and configuration specification bindings. The shared grammar preserves delimiters, separators, formal and actual spans, arrows, explicit `open`, and the VHDL-2008 port `inertial` prefix. Whole-map `<>` and `default` are retained on formal package maps. Association interiors preserve bounded source spans for calls, aggregates, conversions and names. Validation covers the extracted grammar profile.

Concurrent assertions retain the condition and optional report and severity clauses. Concurrent procedure calls retain the name and optional parameter list. Bare labeled names in instance-capable regions make both the instantiation and call inventories partial. Map and parameter association inventories have independent coverage.

Simple, conditional and selected concurrent signal assignments retain the target envelope, delay mechanism, waveform elements and alternative connectors. VHDL-2008 matching selection retains its marker after select. Indexed and sliced suffixes, aggregates and external-name interiors retain bounded source spans. Each assignment retains the value and time-expression spans of its waveform elements.

A process retains its header, typed ending and existing declaration owner. Sensitivity clauses distinguish a list of signal-name spans, the VHDL-2008 all form, an absent clause and a malformed bounded list. The sequential body remains opaque. Entity statement parts admit assertions, passive calls and passive processes. Passivity is a semantic rule.

The concurrent region supports direct or subtree inventories through `concurrent_assertions`, `concurrent_procedure_calls`, `actual_parameter_associations`, `concurrent_signal_assignments`, `process_headers` and `sensitivity_lists`. A bounded malformed parameter or sensitivity list can retain its independently established elements. A failed owner fence withdraws its claims and records loss in the affected inventories.

Configuration-block interiors, unsupported concurrent forms including PSL, sequential statements and expression internals remain opaque. Semantic binding, visibility, type resolution, staticness and elaboration are outside this structural index. VHDL-2019 is unsupported.

## Run an experiment

From the repository root, select an explicit Tcl interpreter and a scratch directory outside the checkout.

~~~bash
runtime=/path/to/tclsh
scratch=$(mktemp -d)
env -u AURIG_EXPERIMENTAL_FRONTEND AURIG_EXPERIMENTAL_SCRATCH="$scratch" \
    "$runtime" test/experimental/private_queries.tcl
~~~

The focused repository-contained tests include candidate families, selected-name policy, owner regions, private queries, nested packages, blocks, generate scopes, instantiation ownership, association-list recovery, shared map sites, concurrent statement families, sensitivity lists and composed coverage. Experimental source fixtures use the .vhd.fixture suffix. Some inherited whole-corpus differential and resource harnesses also need review archives and corpora kept separately from the Git branch. Record which tests and interpreter builds were used. Use the coordinator's qualification kit for native Windows smoke on the exact reviewed revision.

## Qualification

The experimental workflow uses pinned Tcl 8.5.19 and 8.6.14 sources. The published L-R1 baseline `3b993ecc937fcebd19072ce8a76eff55c2c89350` passed both hosted experimental Linux jobs and the inherited Core Linux and Windows jobs. The concurrent grammar increment requires separate qualification. Native Windows and hosted results qualify the revision actually tested. Use the coordinator's verification evidence for the exact revision under review. Use Core's production vhdlscan for production consumers.
