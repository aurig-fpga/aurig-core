# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

set root [file dirname [file dirname [file dirname [file normalize [info script]]]]]
puts "Tcl patchlevel: [info patchlevel]"
puts "Tcl executable: [info nameofexecutable]"
puts "Tcl system encoding: [encoding system]"
if {[info tclversion] ne "8.6"} {
    error "Expected Tcl 8.6 for the Windows CI job"
}
if {[string first " " $root] < 0} {
    error "Expected a Core checkout path containing spaces"
}

# Observe the files sourced by package require on the test package path.
proc record_source {command op} {
    lappend ::loaded_sources [file normalize [lindex $command end]]
}
set loaded_sources {}
trace add execution ::source enter record_source
set version [package require aurig::core]
trace remove execution ::source enter record_source
if {$version ne "0.2.0" || $version ne $::aurig::core::version} {
    error "Expected Core 0.2.0 with matching runtime version, got $version"
}
puts "aurig::core $version from $root"
foreach relative {core.tcl util/vhdl_source.tcl analyze/vhdlscan.tcl} {
    set expected [file normalize [file join $root $relative]]
    if {$expected ni $loaded_sources} {
        error "Expected Core source $expected. Loaded sources: $loaded_sources"
    }
    puts "Loaded $expected"
}
