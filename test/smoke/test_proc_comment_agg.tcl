#!/usr/bin/tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Resolve the script directory once (absolute) so every path below is
# independent of the current working directory.
set scriptDir [file dirname [file normalize [info script]]]
set fixtureDir [file dirname $scriptDir]

# Load the library
set aurig_core_root [file dirname $fixtureDir]
lappend ::auto_path $aurig_core_root
package require aurig::core

puts "Testing comment aggregation for procedures"
puts "==========================================\n"

set pkgFile [file join $fixtureDir demo_util_lib demo_util_pkg.vhd]
set parseDict [::aurig::core::analyze::vhdlscan -in $pkgFile -verbosity 0]
set pkg [lindex [::aurig::core::analyze::q_packages $parseDict] 0]

# Check commentDict
if {[dict exists $parseDict comments line]} {
    set commentDict [dict get $parseDict comments line]
    puts "Checking commentDict for line 919:"
    if {[dict exists $commentDict 919]} {
        puts "  Line 919 exists in commentDict: [dict get $commentDict 919]"
    } else {
        puts "  Line 919 NOT in commentDict"
    }
    puts ""
}

set decls [::aurig::core::analyze::q_pkg_decls $parseDict $pkg]

foreach d $decls {
    if {[dict exists $d kind] && [dict get $d kind] eq "procedure"} {
        puts "Procedure: [dict get $d name]"
        puts "Line: [dict get $d line]"
        if {[dict exists $d comment]} {
            set comment [dict get $d comment]
            puts "Comment:\n---\n$comment\n---"
        } else {
            puts "NO COMMENT"
        }
    }
}
