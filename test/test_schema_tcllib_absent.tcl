#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.
#
# NEGATIVE CONTROL: when tcllib `yaml`/`json` are absent, project-mode loading
# must FAIL LOUDLY with installation guidance and must NOT silently fall back
# to ::aurig::core::util::readYamlMinimal.
#
# We validate against the ACTUAL absence condition (not a mock): a child
# interpreter whose ::auto_path is restricted to the aurig-core tree only, so
# `package require yaml` / `json` genuinely cannot be resolved -- exactly as on
# a host where tcllib is not installed. A tripwire wrapped around
# readYamlMinimal proves the loader never reached the fallback parser.

set script_dir [file dirname [file normalize [info script]]]
set core_root  [file dirname $script_dir]
set core_root_n [file normalize $core_root]

set ::pass 0
set ::fail 0
proc pass {name} { puts "  \[OK\]   $name"; incr ::pass }
proc fail {name msg} { puts "  \[XX\]   $name"; puts "         $msg"; incr ::fail }
proc check {name cond {detail ""}} {
    if {[uplevel 1 [list expr $cond]]} { pass $name } else { fail $name $detail }
}

puts "\n========== schema: tcllib-absent negative control =========="

# Child interp whose ::auto_path is the aurig-core tree plus ONLY the base Tcl
# library ($tcl_library). The base library keeps Tcl's own package/module
# machinery working, while tcllib -- which lives in a DIFFERENT directory the
# parent had on auto_path -- becomes unreachable. This reproduces a host where
# tcllib is simply not installed: `package require yaml` genuinely cannot
# resolve. It is a real absence, not a stubbed/forgotten package.
#
# The "genuinely unreachable" assertions below are the guard: if some host
# layout still exposes tcllib through the kept paths, those assertions FAIL
# loudly rather than letting the rest of the harness pass for the wrong reason.
set child [interp create]
$child eval [list set ::auto_path [list $core_root $::tcl_library]]

# Sanity: the absence must be REAL in this child.
set yaml_rc [$child eval {catch {package require yaml}}]
set json_rc [$child eval {catch {package require json}}]
check "tcllib yaml is genuinely unreachable in the child" {$yaml_rc != 0} \
    "package require yaml unexpectedly succeeded"
check "tcllib json is genuinely unreachable in the child" {$json_rc != 0} \
    "package require json unexpectedly succeeded"

# The core package itself loads fine without tcllib (no runtime dep at source).
set load_rc [$child eval {catch {package require aurig::core} e; set e}]
check "aurig::core still loads without tcllib" \
    {[$child eval {info procs ::aurig::core::schema::scan_project}] ne ""} \
    "core load result: $load_rc"

# Install a tripwire on the fallback parser: if the loader ever calls
# readYamlMinimal, we record it. It must NEVER be called on the project path.
$child eval {
    set ::__rym_called 0
    rename ::aurig::core::util::readYamlMinimal ::__real_readYamlMinimal
    proc ::aurig::core::util::readYamlMinimal {args} {
        set ::__rym_called 1
        return [::__real_readYamlMinimal {*}$args]
    }
}

set manifest [file join $core_root test fixtures manifests project project.yaml]

# require_libs must fail directly with guidance.
set rl_rc [$child eval [list catch [list ::aurig::core::schema::require_libs] ::rl_err]]
set rl_err [$child eval {set ::rl_err}]
check "require_libs FAILS when tcllib absent" {$rl_rc != 0} \
    "require_libs unexpectedly succeeded"
check "require_libs error names tcllib" {[string match -nocase {*tcllib*} $rl_err]} \
    "msg: $rl_err"
check "require_libs error names yaml" {[string match -nocase {*yaml*} $rl_err]} \
    "msg: $rl_err"
check "require_libs error names json" {[string match -nocase {*json*} $rl_err]} \
    "msg: $rl_err"
check "guidance mentions how to install (apt-get/teacup/auto_path)" \
    {[string match -nocase {*apt-get*} $rl_err] || [string match -nocase {*teacup*} $rl_err] || [string match -nocase {*auto_path*} $rl_err]} \
    "msg: $rl_err"

# The full consumer entry must also FAIL (not return a half-parsed view).
set sp_rc [$child eval [list catch [list ::aurig::core::schema::scan_project $manifest] ::sp_err]]
set sp_err [$child eval {set ::sp_err}]
check "scan_project FAILS when tcllib absent" {$sp_rc != 0} \
    "scan_project unexpectedly returned a result"
check "scan_project failure carries the guidance message" \
    {[string match -nocase {*tcllib*} $sp_err]} "msg: $sp_err"

# F2: the LEGACY project-mode YAML entry must also fail loudly and must not
# reach readYamlMinimal. collect_project_files -format yaml previously routed
# through readYaml, whose lite fallback would silently mis-parse a manifest.
set cpf_rc [$child eval [list catch \
    [list ::aurig::core::util::collect_project_files -from $manifest -format yaml] \
    ::cpf_err]]
set cpf_err [$child eval {set ::cpf_err}]
check "collect_project_files -format yaml FAILS when tcllib absent" {$cpf_rc != 0} \
    "collect_project_files unexpectedly returned a result"
check "collect_project_files failure carries tcllib guidance" \
    {[string match -nocase {*tcllib*} $cpf_err]} "msg: $cpf_err"

# FIX 2: yaml2ini is ALSO a project-mode YAML entry (it reads a canonical
# manifest to convert to INI) and previously reached readYamlMinimal silently.
# It must now fail loudly under tcllib-absence with zero fallback reach. We
# point it at a manifest with multi-key file_sets list items -- exactly what the
# lite parser would mis-read -- to make any surviving reach observable.
set y2i_out [file join $core_root test _tmp_absent_out.ini]
set y2i_rc [$child eval [list catch \
    [list ::aurig::core::util::yaml2ini $manifest $y2i_out] ::y2i_err]]
set y2i_err [$child eval {set ::y2i_err}]
check "yaml2ini FAILS when tcllib absent" {$y2i_rc != 0} \
    "yaml2ini unexpectedly succeeded"
check "yaml2ini failure carries tcllib guidance" \
    {[string match -nocase {*tcllib*} $y2i_err]} "msg: $y2i_err"
catch {file delete -force $y2i_out}

# Exported ::validate is reachable without going through load_manifest (a
# downstream consumer holding a pre-normalized dict). Its own pre-flight must
# catch the missing tcllib `json` and produce the same guidance as require_libs
# rather than the bare `can't find package json` Tcl raises for a raw
# `package require`. Capture the options dict across the interp boundary in a
# single round-trip, same technique as test_vhdlscan_error_boundary.tcl uses
# for the AURIG CORE PARSE assertions: `catch` inside `$child eval` binds
# rc/err/opts locally, then a `list` wrapper carries the trio back so embedded
# newlines in the guidance text do not disturb parent-side unpacking.
lassign [$child eval {
    set rc [catch {::aurig::core::schema::validate [list]} err opts]
    list $rc $err $opts
}] v_rc v_err v_opts
check "validate FAILS when tcllib absent" {$v_rc != 0} \
    "validate unexpectedly succeeded"
check "validate failure carries tcllib guidance" \
    {[string match -nocase {*tcllib*} $v_err]} "msg: $v_err"
check "validate guidance mentions how to install (apt-get/teacup/auto_path)" \
    {[string match -nocase {*apt-get*} $v_err] || [string match -nocase {*teacup*} $v_err] || [string match -nocase {*auto_path*} $v_err]} \
    "msg: $v_err"
# The substring checks above prove the guidance text is present; this pin
# proves the error CATEGORY, i.e. that the failure came from schema::_err
# (schema/manifest.tcl:73) and not a stray Tcl error whose message happened to
# contain the same words. Exact-equal, not prefix -- the errorcode has exactly
# three elements at the source.
set v_ec [dict get $v_opts -errorcode]
check "validate errorcode is exactly {AURIG SCHEMA MANIFEST}" \
    {$v_ec eq {AURIG SCHEMA MANIFEST}} \
    "errorcode: $v_ec"

# Per-package guidance branches. require_libs's yaml: and json: explanatory
# bullets were unconditional before #17 -- a json-only failure printed the
# yaml paragraph too. Each branch is now scoped to `$missing`, and each needs
# its own coverage: the both-missing case above cannot distinguish "the yaml
# bullet is present because yaml is missing" from "the yaml bullet is always
# present."
#
# Both tcllib packages are unreachable in this child, but require_libs builds
# `$missing` from what the caller PASSED, not from what happens to be
# unreachable -- so passing an explicit single-package list reaches the
# per-package branch cleanly, without the fragility of monkey-patching
# `package require` in a second child.
foreach {label pkg other} {
    yaml-only yaml json
    json-only json yaml
} {
    $child eval [list set ::__req_pkgs [list $pkg]]
    lassign [$child eval {
        set rc [catch {::aurig::core::schema::require_libs $::__req_pkgs} err opts]
        list $rc $err $opts
    }] rc err opts
    set ec [dict get $opts -errorcode]
    check "$label: FAILS when tcllib absent" {$rc != 0} \
        "require_libs unexpectedly succeeded"
    check "$label: errorcode is exactly {AURIG SCHEMA MANIFEST}" \
        {$ec eq {AURIG SCHEMA MANIFEST}} "errorcode: $ec"
    check "$label: message names the requested package ($pkg)" \
        {[string match -nocase "*$pkg*" $err]} "msg: $err"
    check "$label: message does NOT mention the other package ($other)" \
        {![string match -nocase "*$other*" $err]} "msg: $err"
    check "$label: install guidance still present (apt-get/auto_path)" \
        {[string match -nocase {*apt-get*} $err] || [string match -nocase {*auto_path*} $err]} \
        "msg: $err"
    check "$label: README pointer line present" \
        {[string match {*Requirements section of this project's README*} $err]} \
        "msg: $err"
}

# The headline negative assertion: NO silent fallback to readYamlMinimal from
# ANY project-mode entry exercised above (scan_project, collect_project_files,
# AND yaml2ini).
set rym_called [$child eval {set ::__rym_called}]
check "readYamlMinimal was NEVER used as a silent fallback" {$rym_called == 0} \
    "readYamlMinimal was invoked ($rym_called) -- silent fallback occurred"

interp delete $child

puts "\n========================================"
puts "  passed: $::pass    failed: $::fail"
puts "========================================"
exit [expr {$::fail == 0 ? 0 : 1}]
