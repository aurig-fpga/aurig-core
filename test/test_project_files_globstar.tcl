#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

set script_dir [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_dir]
lappend ::auto_path $aurig_core_root
package require aurig::core
set root_dir $aurig_core_root

# This harness exercises collect_project_files -format yaml, which is now
# tcllib-gated (F2/F3): project-mode YAML loading requires tcllib `yaml` and
# fails loudly rather than silently using the lite parser. When tcllib is
# absent, SKIP cleanly (exit 0) with a clear message instead of aborting
# opaquely at the first collect call. Under CI / any tcllib-present interp the
# harness runs in full, unchanged.
if {[catch {package require yaml}]} {
    puts "SKIP test_project_files_globstar.tcl: requires tcllib 'yaml'\
 (project-mode YAML loading is tcllib-gated; install tcllib to run this harness)."
    exit 0
}

set fixtures_dir [file join $root_dir test fixtures project_files_globstar]
set tests_passed 0
set tests_failed 0

proc pass {name} {
    global tests_passed
    incr tests_passed
    puts "  \[✓\] PASS   $name"
}

proc fail {name msg} {
    global tests_failed
    incr tests_failed
    puts "  \[✗\] FAIL   $name"
    puts "        $msg"
}

proc assert_equal {name expected actual} {
    if {$expected eq $actual} {
        pass $name
    } else {
        fail $name "Expected: $expected; Actual: $actual"
    }
}

proc collect_names {manifest} {
    set files [::aurig::core::util::collect_project_files -from $manifest -format yaml]
    set names [list]
    dict for {k rec} $files {
        lappend names [dict get $rec name]
    }
    return [lsort $names]
}

puts "\n=========================================="
puts "Project File Globstar Tests"
puts "=========================================="

set base_names [collect_names [file join $fixtures_dir base_star.yml]]
assert_equal "**/*.vhd includes base and nested files" \
    [list base_top.vhd deep_file.vhd src_top.vhd sub_file.vhd test_file.vhd] \
    $base_names

set src_names [collect_names [file join $fixtures_dir src_star.yml]]
assert_equal "src/**/*.vhd includes files directly in src and below" \
    [list deep_file.vhd src_top.vhd sub_file.vhd test_file.vhd] \
    $src_names

set src_test_names [collect_names [file join $fixtures_dir src_test_star.yml]]
assert_equal "src/**/test/*.vhd supports zero-or-more directories before test" \
    [list test_file.vhd] \
    $src_test_names

if {[catch {
    ::aurig::core::util::collect_project_files \
        -from [file join $fixtures_dir invalid_star.yml] \
        -format yaml
} err]} {
    if {[string match {*complete path component*} $err]} {
        pass "unsupported partial globstar fails explicitly"
    } else {
        fail "unsupported partial globstar fails explicitly" $err
    }
} else {
    fail "unsupported partial globstar fails explicitly" "Pattern unexpectedly succeeded"
}

set temp_loop [file join $root_dir test temp_globstar_loop]
file delete -force $temp_loop
file mkdir [file join $temp_loop child]
set fh [open [file join $temp_loop top.vhd] w]
puts $fh "entity loop_top is end entity;"
close $fh

set symlink_created 0
if {![catch {file link -symbolic [file join $temp_loop child loop] $temp_loop} link_err]} {
    set symlink_created 1
}

if {$symlink_created} {
    if {[catch {set loop_names [collect_names [file join $fixtures_dir base_star.yml]]} err]} {
        fail "existing globstar fixtures remain readable with symlink support" $err
    } else {
        pass "existing globstar fixtures remain readable with symlink support"
    }

    if {[catch {
        ::aurig::core::util::_expand_glob_pattern [file join $temp_loop ** *.vhd]
    } err]} {
        if {[string match {*maximum depth*} $err]} {
            pass "symlink loop fails with explicit depth error"
        } else {
            fail "symlink loop fails with explicit depth error" $err
        }
    } else {
        pass "symlink loop does not hang"
    }
} else {
    puts "  \[?\] SKIP   symlink loop test: cannot create symlinks in this environment"
    puts "        Windows may require Developer Mode or elevated privileges. Details: $link_err"
}

file delete -force $temp_loop

puts "\n=========================================="
puts "Test Summary"
puts "=========================================="
puts "Total:  [expr {$tests_passed + $tests_failed}]"
puts "Passed: $tests_passed"
puts "Failed: $tests_failed"

if {$tests_failed > 0} {
    exit 1
}
exit 0
