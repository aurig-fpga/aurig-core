#!/usr/bin/tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Test script to verify verbosity levels in vhdlscan

# Load the library
set script_anchor [file dirname [file normalize [info script]]]
set fixture_dir [file dirname $script_anchor]
set aurig_core_root [file dirname $fixture_dir]
lappend ::auto_path $aurig_core_root
package require aurig::core

# Test file
set testFile [file join $fixture_dir test_entity.vhd]

if {![file exists $testFile]} {
    puts "ERROR: Test file not found: $testFile"
    exit 1
}

puts "========================================"
puts "Testing verbosity level 0 (silent)"
puts "========================================"
set result0 [::aurig::core::analyze::vhdlscan -in $testFile -verbosity 0]
puts "Result: [dict size $result0] top-level items found"
puts ""

puts "========================================"
puts "Testing verbosity level 1 (entity/arch only)"
puts "========================================"
set result1 [::aurig::core::analyze::vhdlscan -in $testFile -verbosity 1]
puts "Result: [dict size $result1] top-level items found"
puts ""

puts "========================================"
puts "Testing verbosity level 2 (libraries/packages)"
puts "========================================"
set result2 [::aurig::core::analyze::vhdlscan -in $testFile -verbosity 2]
puts "Result: [dict size $result2] top-level items found"
puts ""

puts "========================================"
puts "Testing verbosity level 3 (DEBUG)"
puts "========================================"
set result3 [::aurig::core::analyze::vhdlscan -in $testFile -verbosity 3]
puts "Result: [dict size $result3] top-level items found"
puts ""

puts "All tests completed successfully!"
