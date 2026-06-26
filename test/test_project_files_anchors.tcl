#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Regression tests for project-file path anchoring.
#
# Covers util/project_files.tcl paths that are resolved relative to an
# explicit manifest/project-file directory rather than canonicalized through
# [file normalize].

set script_dir [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_dir]
lappend ::auto_path $aurig_core_root
package require aurig::core
set root_dir $aurig_core_root

set failures 0
set tmp_dir [file join $root_dir test .tmp_project_files_anchors]

proc assert_true {condition message} {
    global failures
    if {[uplevel 1 [list expr $condition]]} {
        puts "PASS: $message"
    } else {
        puts "FAIL: $message"
        incr failures
    }
}

proc assert_equal {actual expected message} {
    global failures
    if {$actual eq $expected} {
        puts "PASS: $message"
    } else {
        puts "FAIL: $message"
        puts "      expected: $expected"
        puts "      actual:   $actual"
        incr failures
    }
}

proc write_file {path content} {
    set fh [open $path w]
    fconfigure $fh -translation lf -encoding utf-8
    puts -nonewline $fh $content
    close $fh
}

proc first_fullpath {files} {
    set paths {}
    dict for {key rec} $files {
        lappend paths [dict get $rec fullpath]
    }
    return [lindex [lsort $paths] 0]
}

file delete -force $tmp_dir
file mkdir $tmp_dir

set project_dir [file join $tmp_dir project]
set other_cwd [file join $tmp_dir other_cwd]
file mkdir [file join $project_dir rtl]
file mkdir $other_cwd

write_file [file join $project_dir rtl top.vhd] {entity top is end entity;}

set old_cwd [pwd]
cd $other_cwd

write_file [file join $project_dir project.qpf] {PROJECT_REVISION = project}
write_file [file join $project_dir project.qsf] {set_global_assignment -name VHDL_FILE rtl/../rtl/top.vhd}

set quartus_files [::aurig::core::util::collect_project_files \
    -from [file join $project_dir project.qpf] \
    -format quartus]
set quartus_path [first_fullpath $quartus_files]
set expected_quartus_path [file join $project_dir rtl .. rtl top.vhd]
assert_equal $quartus_path $expected_quartus_path "Quartus relative entries resolve against project dir without canonicalization"
assert_true {[file exists $quartus_path]} "Quartus anchored path is usable for file exists"

write_file [file join $project_dir project.ini] [string map [list @PROJECT@ $project_dir] {[config]
workdir = @PROJECT@

[libraries]
work = rtl/../rtl
}]

set ini_files [::aurig::core::util::collect_project_files \
    -from [file join $project_dir project.ini] \
    -format ini]
set ini_path [first_fullpath $ini_files]
set expected_ini_path [file join $project_dir rtl .. rtl top.vhd]
assert_equal $ini_path $expected_ini_path "INI library path resolves against workdir without canonicalization"
assert_true {[file exists $ini_path]} "INI anchored path is usable for file exists"

write_file [file join $project_dir missing.ini] [string map [list @PROJECT@ $project_dir] {[config]
workdir = @PROJECT@

[libraries]
work = missing_sources
}]

set missing_files [::aurig::core::util::collect_project_files \
    -from [file join $project_dir missing.ini] \
    -format ini]
assert_true {[dict size $missing_files] == 0} "INI missing relative library path returns empty inventory"

cd $old_cwd

file delete -force $tmp_dir

if {$failures > 0} {
    exit 1
}

exit 0
