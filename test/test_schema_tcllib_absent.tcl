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
