# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# aurig-core carve proof.
#
# Proves that `package require aurig::core` resolves entirely from the
# aurig-core tree and reaches NO file from any tcl4fpga source tree. We do this
# in a child interpreter whose ::auto_path is ONLY the aurig-core dir plus the
# parent's genuine tcllib/system entries (every entry mentioning a tcl4fpga
# tree is stripped). A recording wrapper around `source` captures every file
# sourced while the package loads; the headline assertion is that all of them
# live under the aurig-core dir.
#
# Note on the query layer: tcl4fpga exposes its parse-dict queries as the
# namespaced procs `::aurig::core::analyze::q_*` (e.g. q_entity_names). There is
# no bare `::q_entity_names` global — neither here nor in the umbrella tree;
# every consumer calls the fully-qualified name — so this guard asserts the
# qualified query proc.
#=============================================================================

set script_anchor [file dirname [file normalize [info script]]]
set core_root [file dirname $script_anchor]
set core_root_n [file normalize $core_root]

set ::pass 0
set ::fail 0
proc ok {label cond} {
    if {[uplevel 1 [list expr $cond]]} {
        puts "PASS: $label"; incr ::pass
    } else {
        puts "FAIL: $label"; incr ::fail
    }
}

# ---------------------------------------------------------------------------
# Build the child's auto_path: aurig-core first, then ONLY parent entries that
# are neither the aurig-core dir nor anything under a tcl4fpga tree.
# ---------------------------------------------------------------------------
set passthrough {}
foreach p $::auto_path {
    set np [file normalize $p]
    if {$np eq $core_root_n} continue
    if {[string match -nocase *aurig-core* $np]} continue
    if {[string match -nocase *tcl4fpga* $np]} continue
    lappend passthrough $p
}

set child [interp create]

# Pre-scan the package index FIRST (sources every pkgIndex.tcl on auto_path,
# including tcllib's) so that the later recording wrapper captures ONLY the
# files sourced by aurig::core's own ifneeded body, not the index scan.
$child eval [list set ::auto_path [linsert $passthrough 0 $core_root]]
$child eval {catch {package require __force_index_scan_nonexistent__}}

# Install the recording wrapper, THEN require the package.
$child eval {
    set ::__sourced {}
    rename ::source ::__real_source
    proc ::source {args} {
        lappend ::__sourced [file normalize [lindex $args end]]
        return [::__real_source {*}$args]
    }
}

set load_rc [catch {$child eval {package require aurig::core}} load_ver]

ok "package require aurig::core succeeds" {$load_rc == 0}
ok "reports a version" {[string length $load_ver] > 0}

# ---------------------------------------------------------------------------
# Headline assertion: every file sourced while loading the package is under
# the aurig-core dir — proving no tcl4fpga-tree file was reached.
# ---------------------------------------------------------------------------
set sourced [$child eval {set ::__sourced}]
ok "at least one file was sourced (core.tcl + closure)" {[llength $sourced] > 0}

set outside {}
foreach s $sourced {
    if {![string equal -length [string length $core_root_n] $s $core_root_n]} {
        lappend outside $s
    }
}
ok "EVERY sourced path is under the aurig-core dir (no tcl4fpga-tree file reached)" \
    {[llength $outside] == 0}
if {[llength $outside]} {
    puts "  offending sourced paths:"
    foreach o $outside { puts "    $o" }
}

# ---------------------------------------------------------------------------
# Core procs resolve (parser stack + query layer + util base).
# ---------------------------------------------------------------------------
proc child_has {ch cmd} { return [llength [$ch eval [list info commands $cmd]]] }

ok "::aurig::core::analyze::vhdlscan resolves" \
    {[child_has $child ::aurig::core::analyze::vhdlscan] == 1}
ok "::aurig::core::analyze::q_entity_names resolves" \
    {[child_has $child ::aurig::core::analyze::q_entity_names] == 1}
ok "::aurig::core::util::collect_project_files resolves" \
    {[child_has $child ::aurig::core::util::collect_project_files] == 1}
ok "::aurig::core::util::readYaml resolves" \
    {[child_has $child ::aurig::core::util::readYaml] == 1}

# ---------------------------------------------------------------------------
# Leaf / lint / doc procs are ABSENT (they are not part of the lean core).
# ---------------------------------------------------------------------------
ok "::aurig::core::analyze::scan_project is ABSENT (leaf)" \
    {[child_has $child ::aurig::core::analyze::scan_project] == 0}
ok "::aurig::core::util::ise2ini is ABSENT (create_ini leaf)" \
    {[child_has $child ::aurig::core::util::ise2ini] == 0}
ok "::aurig::core::lint::run is ABSENT (lint)" \
    {[child_has $child ::aurig::core::lint::run] == 0}
ok "::aurig::core::document::generate_documentation is ABSENT (doc)" \
    {[child_has $child ::aurig::core::document::generate_documentation] == 0}
set doc_any [$child eval {concat [info commands ::aurig::core::document::*] [info commands ::document::*]}]
ok "no ::document:: proc of any kind is present" {[llength $doc_any] == 0}

interp delete $child

puts ""
puts "============================================================"
puts "  passed: $::pass    failed: $::fail"
puts "============================================================"
exit [expr {$::fail == 0 ? 0 : 1}]
