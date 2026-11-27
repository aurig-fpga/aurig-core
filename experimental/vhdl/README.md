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

A process retains its header, typed ending and existing declaration owner. Sensitivity clauses distinguish a list of signal-name spans, the VHDL-2008 all form, an absent clause and a malformed bounded list. Entity statement parts admit assertions, passive calls and passive processes. Passivity is a semantic rule.

Process, function and procedure bodies retain a sequential span distinct from their declarative region. Direct private inventories cover assertions, reports, null, waits, calls and their actuals, returns, next, exit, and variable and signal assignments. Protected operations use their existing subprogram-body owners. Direct leaves are ordered within each inventory, with snapshot-qualified occurrence and owner identities.

Wait preserves explicit on, until and for clauses. Assignments retain target and value spans, connectors and waveform elements. VHDL-2008 adds conditional and selected sequential assignments, matching selection, force assignments and simple release. Older editions accept the simple assignment forms. Expression and name interiors remain opaque within the supported structural envelopes. Context checks on returns are reported separately from their grammar results.

Sequential if and elsif conditions, else clauses, ordinary and VHDL-2008 matching case alternatives, and unconditional, while and for loops retain their headers, typed endings and nested statement sequences. Each alternative or loop body has a snapshot-qualified syntax owner. A for-loop parameter has a distinct role and a bounded discrete range with structural fields where supported. Direct queries return statements in the requested owner. Subtree queries include nested statements in source order. Proved empty sequences have complete inventories. Unproved sequence boundaries withdraw their records and contribute loss evidence while independently fenced siblings can survive. Expressions and names inside these productions remain opaque or partially structured.

The concurrent region supports direct or subtree inventories through `concurrent_assertions`, `concurrent_procedure_calls`, `actual_parameter_associations`, `concurrent_signal_assignments`, `process_headers` and `sensitivity_lists`. A bounded malformed parameter or sensitivity list can retain its independently established elements. A failed owner fence withdraws its claims and records loss in the affected inventories.

Configuration-block interiors, unsupported concurrent forms including PSL and expression internals remain opaque. Semantic binding, visibility, type resolution, staticness and elaboration are outside this structural index. VHDL-2019 is unsupported.

## Bounded name and expression experiment

The private P-A engine can parse one caller-fenced name, expression or discrete range on the existing significant-token tape. Load `bounded.tcl` explicitly after the experimental frontend to use it. The result retains compact syntax rows with normalized source spans, ordered children and connectors, and unresolved syntax candidates for ambiguous forms. The standalone grammar harness also covers edition differences, lexical boundaries, malformed inputs and resource limits. [Grammar profile](BOUNDED_GRAMMAR.md)

Ordinary `analyze_file` and its queries keep opaque expression coverage. Source `payload.tcl` explicitly for owner-aware payload inventories, selective parsing and transient batch validation. These operations use the original snapshot and significant-token tape.

~~~tcl
source [file join $core experimental vhdl payload.tcl]
set unit [lindex [::vhdl_index::query::units $view] 0]
set owner [dict get $unit occurrence_id]
set inventory [::vhdl_index::payload::inventory $view $owner subtree]
foreach slot [dict get $inventory rows] {
    if {[dict get $slot presence] ne "present"} {continue}
    set selected [::vhdl_index::payload::select $view [dict get $slot owner_id] \
        [dict get $slot occurrence_id] [dict get $slot role]]
    puts [dict get $selected status]
    break
}
set batch [::vhdl_index::payload::validate $view [list [list $owner subtree]]]
~~~

Selective results keep a compact arena for that payload. Call `payload::nodes` with selected arena ordinals to materialize node dictionaries. Batch results retain shared status and diagnostic summaries and release each arena during validation. Budget exhaustion returns an incomplete batch and explicit remaining work. Inventory completeness describes the proved structural payload roles in the request. Bounded syntax and semantic denotation have separate outcomes.

Admitted carriers include defaults, initializers, attribute and file expressions, disconnect times, block and generate headers, assertions, sequential conditions and selectors, assignment alternatives, waveform values and times, and proved discrete ranges. Assignment targets, choice roles, sensitivity names, and map or call arguments with contextual grammar need dedicated adapters. Existing markers such as `open`, `others`, `unaffected`, waveform `null`, and process `all` keep their owning syntax. Semantic resolution, unsupported syntax and VHDL-2019 remain outside this experimental profile. [Bounded grammar](BOUNDED_GRAMMAR.md)

## Run an experiment

From the repository root, select an explicit Tcl interpreter and a scratch directory outside the checkout.

~~~bash
runtime=/path/to/tclsh
scratch=$(mktemp -d)
env -u AURIG_EXPERIMENTAL_FRONTEND AURIG_EXPERIMENTAL_SCRATCH="$scratch" \
    "$runtime" test/experimental/private_queries.tcl
~~~

The focused repository-contained tests include candidate families, selected-name policy, owner regions, private queries, nested packages, blocks, generate scopes, instantiation ownership, association-list recovery, shared map sites, concurrent statement families, sensitivity lists, sequential leaves, nested control flow and composed coverage. Experimental source fixtures use the .vhd.fixture suffix. Some inherited whole-corpus differential and resource harnesses also need review archives and corpora kept separately from the Git branch. Record which tests and interpreter builds were used. Use the coordinator's qualification kit for native Windows smoke on the exact reviewed revision.

## Qualification

The experimental workflow uses pinned Tcl 8.5.19 and 8.6.14 sources. Published P-A at `889a55b83fff83efe13e930c691de4a740186336` passed both hosted experimental Linux jobs and the inherited Core Linux, Windows and pre-commit jobs. Hosted and native Windows experimental qualification are specific to the tested revision. Use Core's production vhdlscan for production consumers.
