#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Regression tests for Quartus project file collection.
#
# Covers the .qpf -> .qsf fallback path in util/project_files.tcl. This
# protects the pattern-form glob used by GLOB-DEBT-002 from regressing back
# to fragile `glob -directory` usage.

set script_dir [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_dir]
lappend ::auto_path $aurig_core_root
package require aurig::core
set root_dir $aurig_core_root

set failures 0
set tmp_dir [file join $root_dir test .tmp_project_files_quartus]

proc assert_true {condition message} {
    global failures
    if {[uplevel 1 [list expr $condition]]} {
        puts "PASS: $message"
    } else {
        puts "FAIL: $message"
        incr failures
    }
}

proc write_file {path content} {
    set fh [open $path w]
    fconfigure $fh -translation lf -encoding utf-8
    puts -nonewline $fh $content
    close $fh
}

proc collect_names {manifest} {
    set files [::aurig::core::util::collect_project_files \
        -from $manifest \
        -format quartus]
    set names {}
    dict for {key rec} $files {
        lappend names [dict get $rec name]
    }
    return [lsort $names]
}

file delete -force $tmp_dir
file mkdir $tmp_dir

set same_dir [file join $tmp_dir same_basename]
file mkdir $same_dir
write_file [file join $same_dir project.qpf] {PROJECT_REVISION = project}
write_file [file join $same_dir project.qsf] {set_global_assignment -name VHDL_FILE rtl/top.vhd}
file mkdir [file join $same_dir rtl]
write_file [file join $same_dir rtl top.vhd] {entity top is end entity;}

set same_names [collect_names [file join $same_dir project.qpf]]
assert_true {"top.vhd" in $same_names} "same-basename .qsf path collects VHDL file"

set fallback_dir [file join $tmp_dir fallback]
file mkdir $fallback_dir
write_file [file join $fallback_dir project.qpf] {PROJECT_REVISION = other}
write_file [file join $fallback_dir other.qsf] {set_global_assignment -name VHDL_FILE rtl/fallback_top.vhd}
file mkdir [file join $fallback_dir rtl]
write_file [file join $fallback_dir rtl fallback_top.vhd] {entity fallback_top is end entity;}

set fallback_names [collect_names [file join $fallback_dir project.qpf]]
assert_true {"fallback_top.vhd" in $fallback_names} "fallback glob finds alternate .qsf"

set no_qsf_dir [file join $tmp_dir no_qsf]
file mkdir $no_qsf_dir
write_file [file join $no_qsf_dir project.qpf] {PROJECT_REVISION = missing}

set no_qsf_files [::aurig::core::util::collect_project_files \
    -from [file join $no_qsf_dir project.qpf] \
    -format quartus]
assert_true {[dict size $no_qsf_files] == 0} "missing .qsf returns empty dict"

set missing_files [::aurig::core::util::collect_project_files \
    -from [file join $tmp_dir missing project.qpf] \
    -format quartus]
assert_true {[dict size $missing_files] == 0} "non-existent Quartus directory returns empty dict"

set old_cwd [pwd]
cd $root_dir
set rel_names [collect_names [file join . test .tmp_project_files_quartus fallback project.qpf]]
assert_true {"fallback_top.vhd" in $rel_names} "relative .qpf path exercises fallback glob"
cd $old_cwd

file delete -force $tmp_dir

if {$failures > 0} {
    exit 1
}

exit 0
