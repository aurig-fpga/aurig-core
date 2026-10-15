#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Use-clause fields hold what they name (#62).
#
# `use ieee.std_logic_1164.all;` was recorded as lib=std_logic_1164, pkg=all,
# selector={}, decl=ieee: the regexp had lost its whole-match group while the
# caller still bound four values. A use clause is now recorded as lib (the
# library), pkg (the package), selector (the item) and decl (the full clause,
# like a library declaration). The two-part form `use lib.pkg;` names a
# package; `use lib.all;` names none.
#
# Controls: record counts and every line number (of the records and of what
# follows them) are unchanged, including after multi-line clauses.

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set ::pass_count 0
set ::fail_count 0
set ::tmp_files {}
set ::tmp_dir ""

# Equality assertion that prints the observed value on failure, so a run on an
# unpatched tree documents what it returned.
proc check_eq {label got expected} {
    if {$got eq $expected} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        set g [string map {\n {\n}} $got]
        set x [string map {\n {\n}} $expected]
        puts "FAIL: $label (expected \"$x\", got \"$g\")"
        incr ::fail_count
    }
}

# Fixtures are written to a unique per-run directory under the system temp
# directory (TMPDIR, TEMP or TMP; else /tmp; else the current directory) and
# removed in a finally block.
proc make_tmp_dir {} {
    set base ""
    foreach var {TMPDIR TEMP TMP} {
        if {[info exists ::env($var)] && [file isdirectory $::env($var)]} {
            set base $::env($var)
            break
        }
    }
    if {$base eq ""} {
        set base [expr {[file isdirectory /tmp] ? "/tmp" : [pwd]}]
    }
    set dir [file join $base "aurig_core_use_clauses_[pid]_[clock milliseconds]"]
    file mkdir $dir
    return $dir
}

# Write a fixture from a list of lines (LF, binary mode: no translation).
proc tmp_vhd_lines {basename lines} {
    set path [file join $::tmp_dir "${basename}.vhd"]
    lappend ::tmp_files $path
    set fp [open $path w]
    try {
        fconfigure $fp -translation binary
        puts -nonewline $fp "[join $lines \n]\n"
    } finally {
        close $fp
    }
    return $path
}

proc cleanup_tmp_files {} {
    foreach path $::tmp_files {
        catch {file delete -- $path}
    }
    if {$::tmp_dir ne ""} {
        catch {file delete -force -- $::tmp_dir}
    }
}

# Parse the clause lines followed by a small entity; return {uses entityLine}.
set ::entity_tail {
    {entity e is}
    {  port (clk : in bit);}
    {end entity e;}
}
proc parse_uses {basename lines} {
    set D [::aurig::core::analyze::vhdlscan \
        -in [tmp_vhd_lines $basename [concat $lines $::entity_tail]] -verbosity 0]
    set uses [expr {[dict exists $D uses] ? [dict get $D uses] : {}}]
    return [list $uses [dict get [lindex [dict get $D entities] 0] line]]
}

# Field $key of record $r, or "<absent>".
proc fld {r key} {
    expr {[dict exists $r $key] ? [dict get $r $key] : "<absent>"}
}

# The fields of one record as {lib pkg selector decl}.
proc fields {r} {
    list [fld $r lib] [fld $r pkg] [fld $r selector] [fld $r decl]
}

set ::tmp_dir [make_tmp_dir]
try {
    # --- Field values, one clause per fixture ---------------------------------
    foreach {label lines lib pkg selector decl} {
        "ieee.std_logic_1164.all"
            {{library ieee;} {use ieee.std_logic_1164.all;}}
            ieee std_logic_1164 all {use ieee.std_logic_1164.all;}
        "ieee.numeric_std.all"
            {{library ieee;} {use ieee.numeric_std.all;}}
            ieee numeric_std all {use ieee.numeric_std.all;}
        "work.my_pkg.my_function"
            {{use work.my_pkg.my_function;}}
            work my_pkg my_function {use work.my_pkg.my_function;}
        "uppercase IEEE.STD_LOGIC_1164.ALL"
            {{LIBRARY IEEE;} {USE IEEE.STD_LOGIC_1164.ALL;}}
            IEEE STD_LOGIC_1164 ALL {USE IEEE.STD_LOGIC_1164.ALL;}
        "selector list work.my_pkg.f_one, f_two"
            {{use work.my_pkg.f_one, f_two;}}
            work my_pkg {f_one, f_two} {use work.my_pkg.f_one, f_two;}
        "multi-line ieee. / std_logic_1164.all"
            {{library ieee;} {use ieee.} {    std_logic_1164.all;}}
            ieee std_logic_1164 all "use ieee.\nstd_logic_1164.all;"
    } {
        set r [lindex [lindex [parse_uses [string map {" " _ . _ / _ , _} $label] $lines] 0] 0]
        check_eq "$label: lib" [fld $r lib] $lib
        check_eq "$label: pkg" [fld $r pkg] $pkg
        check_eq "$label: selector" [fld $r selector] $selector
        check_eq "$label: decl is the full clause" [fld $r decl] $decl
    }

    # --- Two-part forms ---------------------------------------------------------
    # `use lib.pkg;` names a package; `use lib.all;` names none.
    set r [lindex [lindex [parse_uses twopart {{library ieee;} {use ieee.std_logic_1164;}}] 0] 0]
    # Asserted as one record: on the shifted parser pkg and selector alone
    # came out right by coincidence, with lib empty.
    check_eq "two-part ieee.std_logic_1164: lib, pkg and an empty selector" \
        [list [fld $r lib] [fld $r pkg] [fld $r selector]] {ieee std_logic_1164 {}}
    check_eq "two-part ieee.std_logic_1164: decl" [fld $r decl] {use ieee.std_logic_1164;}
    set r [lindex [lindex [parse_uses liball {{use work.all;}}] 0] 0]
    check_eq "two-part work.all: lib" [fld $r lib] work
    check_eq "two-part work.all: no pkg" [fld $r pkg] "<absent>"
    check_eq "two-part work.all: selector" [fld $r selector] all
    check_eq "two-part work.all: decl" [fld $r decl] {use work.all;}

    # --- Several clauses in one file --------------------------------------------
    lassign [parse_uses several {
        {library ieee;}
        {use ieee.std_logic_1164.all;}
        {use ieee.numeric_std.all;}
        {use work.my_pkg.my_function;}
    }] uses eline
    foreach r $uses exp {
        {ieee std_logic_1164 all {use ieee.std_logic_1164.all;}}
        {ieee numeric_std all {use ieee.numeric_std.all;}}
        {work my_pkg my_function {use work.my_pkg.my_function;}}
    } {
        check_eq "several: [join [lrange $exp 0 2] .]" [fields $r] $exp
    }
    check_eq "control: several has 3 records" [llength $uses] 3
    check_eq "control: several record lines" [lmap r $uses {dict get $r line}] {2 3 4}
    check_eq "control: several entity line" $eline 5

    # --- A blank or comment line before a clause --------------------------------
    # The clause is matched once, at its own line.
    lassign [parse_uses blank_before {
        {library ieee;}
        {}
        {use ieee.std_logic_1164.all;}
        {-- a comment line}
        {use ieee.numeric_std.all;}
        {}
    }] uses eline
    check_eq "blank or comment line before a clause: one record per clause" [llength $uses] 2
    check_eq "blank or comment line before a clause: record lines" \
        [lmap r $uses {dict get $r line}] {3 5}
    check_eq "control: entity after blank and comment lines" $eline 7

    # --- Line accounting after multi-line clauses (controls) --------------------
    foreach {label lines recLines entityLine} {
        "one multi-line clause"
            {{library ieee;} {use ieee.} {    std_logic_1164.all;}}
            {2} 4
        "two multi-line clauses in a row"
            {{library ieee;} {use ieee.} {    std_logic_1164.all;} {use ieee.} {    numeric_std.all;}}
            {2 4} 6
        "a clause over three lines"
            {{library ieee;} {use} {  ieee.} {    std_logic_1164.all;}}
            {2} 5
        "multi-line and single-line clauses mixed"
            {{library ieee;} {use ieee.std_logic_1164.all;} {use ieee.} {    numeric_std.all;} {use work.my_pkg.my_function;} {use work.} {  other_pkg.} {  all;}}
            {2 3 5 6} 9
    } {
        lassign [parse_uses [string map {" " _} $label] $lines] uses eline
        check_eq "control: $label: record lines" [lmap r $uses {dict get $r line}] $recLines
        check_eq "control: $label: entity line" $eline $entityLine
    }
} finally {
    cleanup_tmp_files
}

puts ""
puts "Passed: $::pass_count"
puts "Failed: $::fail_count"
exit [expr {$::fail_count > 0}]
