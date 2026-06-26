#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.
#
# Project-mode manifest schema tests (::aurig::core::schema), happy path.
# Requires tcllib `yaml` + `json` (present on CI). The COMPLEMENTARY
# negative-control harness (test_schema_tcllib_absent.tcl) proves the
# load FAILS loudly when those packages are missing.

set script_dir [file dirname [file normalize [info script]]]
set core_root  [file dirname $script_dir]
lappend ::auto_path $core_root
package require aurig::core

set fixtures [file join $core_root test fixtures manifests]

set ::pass 0
set ::fail 0
proc pass {name} { puts "  \[OK\]   $name"; incr ::pass }
proc fail {name msg} { puts "  \[XX\]   $name"; puts "         $msg"; incr ::fail }
proc check {name cond {detail ""}} {
    if {[uplevel 1 [list expr $cond]]} { pass $name } else { fail $name $detail }
}

# Hard prerequisite: this harness exercises the real pipeline, so tcllib must
# be present. If it is not, FAIL loudly (do not silently skip) -- a green run
# here must mean the pipeline actually ran.
if {[catch {::aurig::core::schema::require_libs} e]} {
    puts "FATAL: tcllib yaml/json required to run this harness:"
    puts $e
    exit 1
}

puts "\n========== schema: drift / checksum guard =========="
check "verify_schema_checksum passes for the pinned vendored copy" \
    {[::aurig::core::schema::verify_schema_checksum] == 1}

puts "\n========== schema: VALID corpus loads (normalize+validate) =========="
foreach f [lsort [glob -nocomplain [file join $fixtures valid *.yaml]]] {
    set name "valid/[file tail $f]"
    if {[catch {::aurig::core::schema::load_manifest $f} res]} {
        fail "$name loads" $res
    } else {
        pass "$name loads"
    }
}

puts "\n========== schema: INVALID corpus is rejected =========="
# Each invalid manifest must FAIL, and we assert the *real* failure mode
# (not merely "an error happened").
set invalid_expect {
    missing_schema_version.yaml      "missing required key 'schema_version'"
    wrong_schema_version.yaml        "does not match pattern"
    bad_synth_kind.yaml              "is not one of"
    device_missing_vendor.yaml       "missing required key 'vendor'"
    fileset_entry_missing_src.yaml   "missing required key 'src'"
    bad_vhdl_std.yaml                "matches none of oneOf"
    bad_sim_kind.yaml                "isim"
    sim_direct_no_kind.yaml          "missing required key 'kind'"
    empty_object.yaml                "missing required key 'schema_version'"
    device_empty.yaml                "missing required key 'vendor'"
    synth_empty.yaml                 "missing required key 'kind'"
    fileset_src_empty.yaml           "fewer than minItems 1 items"
}
foreach {file needle} $invalid_expect {
    set f [file join $fixtures invalid $file]
    set name "invalid/$file rejected"
    if {[catch {::aurig::core::schema::load_manifest $f} err]} {
        if {[string match "*$needle*" $err]} {
            pass "$name (matched: $needle)"
        } else {
            fail "$name wrong reason" "expected to contain '$needle', got:\n$err"
        }
    } else {
        fail "$name" "manifest unexpectedly loaded clean"
    }
}

puts "\n========== schema: MUST-ACCEPT arrays (round-1 false-reject regression) =========="
# These multi-element / multi-object array shapes were FALSE-REJECTED in round 1
# ("expected type array") because a 2-element list of filename-like strings is
# indistinguishable from a 1-pair dict. Option A: core validate must never
# false-reject valid input. They MUST now load clean. (Entries carry the schema-
# required `lib` so this is a genuine PASS, not a false-green on an incomplete
# manifest.) The shapes: board.xdc_files [2 files], include_dirs_global [2 dirs],
# file_sets.rtl [array of 2 objects], one entry's src [2 files].
set ma [file join $fixtures valid multifile_arrays.yaml]
if {[catch {::aurig::core::schema::load_manifest $ma} mae]} {
    fail "multi-element/multi-object arrays accepted" \
        "FALSE-REJECT regressed:\n$mae"
} else {
    pass "multi-element/multi-object arrays accepted (board+includes+src 2-elt, rtl 2 objects)"
}

puts "\n========== schema: minItems is DECIDABLE (fires regardless of _is_map) =========="
# R7: minItems is a count, decidable even when the value LOOKS like a map.
# Probe the validator directly with a synthetic {type array minItems 3}.
proc _minitems_errs {value min} {
    set errs {}; set warns {}
    ::aurig::core::schema::_validate $value \
        [dict create type array minItems $min items [dict create type string]] \
        {} "<a>" errs warns 0
    return $errs
}
check "minItems 3 rejects map-looking 'alpha beta' (2)" \
    {[string match {*fewer than minItems 3*} [_minitems_errs {alpha beta} 3]]} \
    "errs=[_minitems_errs {alpha beta} 3]"
check "minItems 3 accepts a genuine 3-item array" \
    {[_minitems_errs {a b c} 3] eq ""}
check "minItems 1 accepts a valid 2-item array (no new false-reject)" \
    {[_minitems_errs {a.vhd b.vhd} 1] eq ""}
check "minItems 1 rejects an empty array" \
    {[string match {*fewer than minItems 1*} [_minitems_errs {} 1]]}

puts "\n========== schema: MUST-ACCEPT multi-word scalars (round-2 false-reject gap) =========="
# Multi-word scalar values (project_name "Foo Bar", device.family "Artix 7",
# sim.options "fast mode", generics.MODE "fast mode") were FALSE-REJECTED: a
# scalar with >1 token is indistinguishable in Tcl from a mapping, and the
# round-2 `string` type check rejected map-looking values. Round-3 root cause:
# scalar types accept ANY value. They MUST load clean with values preserved.
set mw [file join $fixtures valid multiword_scalars.yaml]
if {[catch {::aurig::core::schema::load_manifest $mw} r]} {
    fail "multi-word scalars accepted" "FALSE-REJECT regressed:\n$r"
} else {
    lassign $r mwcfg mwwarns
    check "multi-word project_name preserved" {[dict get $mwcfg project_name] eq "Foo Bar"}
    check "multi-word device.family preserved" {[dict get $mwcfg device family] eq "Artix 7"}
    check "multi-word sim.options preserved" {[dict get $mwcfg sim options] eq "fast mode"}
    check "multi-word generics value preserved" {[dict get $mwcfg generics MODE] eq "fast mode"}
}

puts "\n========== schema: forward-compat unknown keys WARN, not reject =========="
# A top-level `$schema:` (JSON-schema convenience key) and any future/unknown
# key must LOAD with an unknown-key WARNING -- never a hard reject. Earlier the
# `$`-prefixed key made `_is_map` mis-classify the whole manifest and reject it
# at read/validate time.
set fc [file join $fixtures valid forward_compat_schema_key.yaml]
if {[catch {::aurig::core::schema::load_manifest $fc} r]} {
    fail "forward-compat \$schema key loads" "hard-rejected:\n$r"
} else {
    lassign $r fccfg fcwarns
    set saw_schema 0; set saw_future 0
    foreach w $fcwarns {
        if {[string match {*$schema*unknown key*} $w]}             { set saw_schema 1 }
        if {[string match {*future_unknown_key*unknown key*} $w]}  { set saw_future 1 }
    }
    pass "forward-compat manifest with \$schema loads (no hard reject)"
    check "\$schema produces an unknown-key WARNING" {$saw_schema == 1}
    check "future unknown key produces a WARNING" {$saw_future == 1}
}

puts "\n========== schema: scan_project consumer (project.yaml) =========="
set view [::aurig::core::schema::scan_project [file join $fixtures project project.yaml]]

check "project_name consumed" {[dict get $view project_name] eq "fixture_project"}
check "schema_version consumed" {[dict get $view schema_version] eq "1"}
check "device.vendor consumed read-only" {[dict get $view device_vendor] eq "xilinx"}

# top name->file resolution: no top_file in manifest, resolved by scanning rtl.
set tf [dict get $view top_file]
check "top resolved to src/top_entity.vhd by entity scan" \
    {[string match "*src/top_entity.vhd" $tf]} "top_file=$tf"

set rtl [dict get $view file_sets rtl]
set sim [dict get $view file_sets sim]
check "file_sets.rtl globbed (top_entity.vhd + helper.vhd)" {[llength $rtl] == 2} \
    "rtl=$rtl"
check "file_sets.sim globbed (top_tb.vhd)" {[llength $sim] == 1} "sim=$sim"
check "sim entry library is tb" {[dict get [lindex $sim 0] lib] eq "tb"}

# external_libraries consumed; legacy 'libraries' never appears in the view.
set el [dict get $view external_libraries]
check "external_libraries consumed (unisim)" {[dict get $el unisim] eq "ignore"}
check "external_libraries consumed (mylib)" \
    {[dict get $el mylib] eq "/opt/precompiled/mylib"}
check "view carries NO legacy 'libraries' key" {![dict exists $view libraries]}
check "generics consumed" {[dict get $view generics WIDTH] eq "8"}

puts "\n========== schema: ATOMIC rename end-to-end (project_legacy.yaml) =========="
# This manifest uses the LEGACY `libraries:` key. The normalize producer must
# rename it, and the scan_project consumer must read `external_libraries` --
# proving both sides moved together and the old key is no longer read.
set legacy_path [file join $fixtures project project_legacy.yaml]
lassign [::aurig::core::schema::load_manifest $legacy_path] lcfg lwarns
check "normalized cfg has external_libraries" {[dict exists $lcfg external_libraries]}
check "normalized cfg DROPPED legacy libraries" {![dict exists $lcfg libraries]}
set saw_rename 0
foreach w $lwarns {
    if {[string match "*libraries is deprecated; renamed to external_libraries*" $w]} {
        set saw_rename 1
    }
}
check "rename emits a deprecation warning" {$saw_rename == 1}

set lview [::aurig::core::schema::scan_project $legacy_path]
set lel [dict get $lview external_libraries]
check "consumer reads renamed external_libraries (unisim)" \
    {[dict get $lel unisim] eq "ignore"}
check "consumer reads renamed external_libraries (mylib)" \
    {[dict get $lel mylib] eq "/opt/precompiled/mylib"}
check "legacy device.vendor altera normalized to intel" \
    {[dict get $lview device_vendor] eq "intel"}

puts "\n========== schema: .local overlay deep-merge =========="
set base [file join $fixtures overlay base.yaml]
set merged [::aurig::core::schema::read_manifest $base]
check "scalar REPLACE: top overridden by overlay" \
    {[dict get $merged top] eq "overridden_top"}
check "dict DEEP-MERGE: tool.synth.version overridden" \
    {[dict get $merged tool synth version] eq "2024.2"}
check "dict DEEP-MERGE: tool.synth.kind preserved from base" \
    {[dict get $merged tool synth kind] eq "vivado"}
check "dict DEEP-MERGE: external_libraries gains overlay key" \
    {[dict get $merged external_libraries mylib] eq "/opt/precompiled/mylib"}
check "dict DEEP-MERGE: external_libraries keeps base key" \
    {[dict get $merged external_libraries unisim] eq "ignore"}
check "dict DEEP-MERGE: generics WIDTH overridden to 16" \
    {[dict get $merged generics WIDTH] eq "16"}
check "EMPTY overlay value IGNORED: device.family kept from base" \
    {[dict get $merged device family] eq "artix7"}
# The merged document must still normalize + validate cleanly.
if {[catch {::aurig::core::schema::load_manifest $base} mres]} {
    fail "merged manifest still validates" $mres
} else {
    pass "merged manifest still validates"
}

puts "\n========== schema: top name->file resolution (F3) =========="
set proj [file join $fixtures project]

# top_file present, exists, declares top -> resolves ("both present").
set v1 [::aurig::core::schema::scan_project [file join $proj project_topfile.yaml]]
check "top_file present+exists+declares top resolves" \
    {[string match "*src/top_entity.vhd" [dict get $v1 top_file]]} \
    "top_file=[dict get $v1 top_file]"

# top_file present but missing on disk -> clear error.
if {[catch {::aurig::core::schema::scan_project [file join $proj project_topfile_missing.yaml]} e1]} {
    check "missing top_file errors clearly" \
        {[string match "*does not exist*" $e1]} "msg: $e1"
} else {
    fail "missing top_file errors clearly" "scan_project unexpectedly succeeded"
}

# top_file present but declares a different entity than top -> clear error.
if {[catch {::aurig::core::schema::scan_project [file join $proj project_topfile_wrongdecl.yaml]} e2]} {
    check "top_file not declaring top errors clearly" \
        {[string match "*does not declare the top entity*" $e2]} "msg: $e2"
} else {
    fail "top_file not declaring top errors clearly" "scan_project unexpectedly succeeded"
}

# top_file absent + multiple RTL files declare top -> error listing candidates
# (must NOT silently pick the first).
if {[catch {::aurig::core::schema::scan_project [file join $fixtures top_multi project.yaml]} e3]} {
    check "ambiguous top across multiple RTL files errors" \
        {[string match "*declared in multiple RTL files*" $e3]} "msg: $e3"
    check "ambiguity error names both candidates" \
        {[string match "*a.vhd*" $e3] && [string match "*b.vhd*" $e3]} "msg: $e3"
    check "ambiguity error points at top_file as disambiguator" \
        {[string match -nocase "*top_file*" $e3]} "msg: $e3"
} else {
    fail "ambiguous top across multiple RTL files errors" "scan_project unexpectedly succeeded"
}

puts "\n========================================"
puts "  passed: $::pass    failed: $::fail"
puts "========================================"
exit [expr {$::fail == 0 ? 0 : 1}]
