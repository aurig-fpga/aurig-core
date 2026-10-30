# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# A tick directly after a word: character literal or qualifier/attribute tick?
#
# _char_literal_at looks at the character before the tick and, when that
# character is part of a word, at the whole word. After an identifier
# (t'length, band'('x')) the tick is a qualifier or attribute tick; after a
# reserved word other than `all` it opens a character literal: in
# `true and';'=';'` the tick after `and` opens the literal ';'. Read as an
# attribute tick, the ';' inside the literal would end the declaration early,
# and with '"' a string would open and run on.
#
# Three scans call the predicate: _nextw, _classify_subprogram_header and
# _find_vhdl_statement_semicolon. Each of them reaches the tick in several
# cases; the comment on each case names the one whose answer alone decides
# it. Cases 1, 2, 3 and 4: _find_vhdl_statement_semicolon, through the
# constant, signal and variable scanners. Case 8, a parameter default:
# _classify_subprogram_header. Case 10, a process statement: _nextw, through
# _find_end_of_process. Cases 5, 6, 7 and 9 are controls: an identifier
# ending in "and", `all` and signature prefixes, and the tick literal. Cases
# 11 and 11b qualify with an extended identifier: \my type\'('x') is a
# control, \my type\'('"') is decided by _find_vhdl_statement_semicolon.
#
# Every lookup into the parse result is guarded: a missing architecture, record or field makes the assertion FAIL
# and the script go on, so every case is reported.
#=============================================================================

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set ::pass_count 0
set ::fail_count 0
set ::tmp_files {}
set ::tmp_dir ""

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
    set dir [file join $base "aurig_core_char_literal_prefix_word_[pid]_[clock milliseconds]"]
    file mkdir $dir
    return $dir
}

# Write a fixture from a list of lines, in binary mode so no translation
# happens on any platform. The path is registered for cleanup before the
# file is created, and the channel is closed in a finally clause.
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

# Fixture: entity e, architecture rtl whose declarative part is $decl
# followed by `constant m` and `signal s`, and whose body is $body followed
# by process p_after. m, s and p_after are what a run-on scan would lose.
proc arch_fixture {basename decl {body {}} {context {}}} {
    set lines $context
    lappend lines {entity e is} {end entity;} {architecture rtl of e is}
    lappend lines {*}$decl
    lappend lines {  constant m : integer := 1;} {  signal s : integer;}
    lappend lines {begin}
    lappend lines {*}$body
    lappend lines {  p_after : process} {  begin} {    wait;} {  end process;}
    lappend lines {end architecture rtl;}
    return [tmp_vhd_lines $basename $lines]
}

# The single architecture of $path, or an error naming why there is none.
proc the_arch {path} {
    if {[catch {::aurig::core::analyze::vhdlscan -in $path -verbosity 0} parsed]} {
        error "vhdlscan raised: $parsed"
    }
    if {![dict exists $parsed architectures]} {
        error "no architectures key"
    }
    set archs [dict get $parsed architectures]
    if {[llength $archs] != 1} {
        error "[llength $archs] architectures"
    }
    return [lindex $archs 0]
}

# Field $field of record $rec. Architecture declarations keep type, init and
# params in the first element of `args`; process declarations keep them at
# the top level. Raises when the field is absent.
proc rec_field {rec field} {
    if {[dict exists $rec $field]} {
        return [dict get $rec $field]
    }
    if {[dict exists $rec args]} {
        set a [lindex [dict get $rec args] 0]
        if {[dict exists $a $field]} {
            return [dict get $a $field]
        }
    }
    error "no field $field"
}

# The record of kind $kind and name $name in $recs (name case-insensitive),
# or an error.
proc find_rec {recs kind name} {
    foreach r $recs {
        if {[dict exists $r kind] && [dict exists $r name]
                && [dict get $r kind] eq $kind
                && [string equal -nocase [dict get $r name] $name]} {
            return $r
        }
    }
    error "no $kind $name"
}

# The process labelled $label in $arch, or an error.
proc find_process {arch label} {
    if {![dict exists $arch processes]} {
        error "no processes key"
    }
    foreach p [dict get $arch processes] {
        if {[dict exists $p label] && [dict get $p label] eq $label} {
            return $p
        }
    }
    error "no process $label"
}

# Run one case. $checks is a list of checks, each one of:
#   decl <kind> <name> [<field> <value>]   architecture declaration
#   pdecl <process> <kind> <name> [<field> <value>]   process declaration
#   process <label>                         process present
# Every check runs; the case PASSes when all hold. A failure prints each
# check that did not hold with what was observed, and never aborts the run.
proc run_case {label path checks} {
    set problems {}
    if {[catch {the_arch $path} arch]} {
        lappend problems $arch
    } else {
        foreach c $checks {
            set what [lindex $c 0]
            set rc [catch {
                switch -- $what {
                    decl {
                        lassign $c - kind name field want
                        set recs [expr {[dict exists $arch declarations] ? [dict get $arch declarations] : {}}]
                        set r [find_rec $recs $kind $name]
                    }
                    pdecl {
                        lassign $c - plabel kind name field want
                        set p [find_process $arch $plabel]
                        set recs [expr {[dict exists $p declarations] ? [dict get $p declarations] : {}}]
                        set r [find_rec $recs $kind $name]
                    }
                    process {
                        lassign $c - plabel
                        set field ""
                        find_process $arch $plabel
                    }
                    default {
                        error "unknown check $what"
                    }
                }
                if {$field ne ""} {
                    set got [rec_field $r $field]
                    if {$got ne $want} {
                        error "$kind $name $field: expected {$want}, got {$got}"
                    }
                }
            } msg]
            if {$rc} {
                lappend problems $msg
            }
        }
    }
    if {[llength $problems] == 0} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label"
        foreach p $problems {
            puts "      $p"
        }
        incr ::fail_count
    }
}

# Checks shared by every fixture: what follows the case under test.
set after {
    {decl constant m init 1}
    {decl signal s}
    {process p_after}
}

set ::tmp_dir [make_tmp_dir]
try {

# ----------------------------------------------------------------------------
# A character literal directly after a reserved word
# ----------------------------------------------------------------------------
# Decided by _find_vhdl_statement_semicolon: the tick after `and` opens the
# literal ';', so the ';' inside it does not end the statement. Taken for an
# attribute tick, it would cut init to `true and'`.
run_case "case 1: constant k : boolean := true and';'=';'" \
    [arch_fixture c1_constant {
        {  constant k : boolean := true and';'=';';}
    }] \
    [list {decl constant k init {true and';'=';'}} {*}$after]

# Decided by _find_vhdl_statement_semicolon, through the signal scanner.
run_case "case 2: signal g : boolean := true and';'=';'" \
    [arch_fixture c2_signal {
        {  signal g : boolean := true and';'=';';}
    }] \
    [list {decl signal g init {true and';'=';'}} {*}$after]

# Decided by _find_vhdl_statement_semicolon, through the variable scanner,
# which reports a shared variable as kind variable. A shared variable of a
# non-protected type is legal only before VHDL-2000 (GHDL accepts this
# fixture with --std=93 and rejects it with --std=08); the case is kept for
# legacy code.
run_case "case 3: shared variable k : boolean := true and';'=';'" \
    [arch_fixture c3_shared_variable {
        {  shared variable k : boolean := true and';'=';';}
    }] \
    [list {decl variable k init {true and';'=';'}} {*}$after]

# Decided by _find_vhdl_statement_semicolon; reserved words are
# case-insensitive, so upper case must behave as case 1.
run_case "case 4: constant k : boolean := TRUE AND';'=';'" \
    [arch_fixture c4_upper {
        {  constant k : boolean := TRUE AND';'=';';}
    }] \
    [list {decl constant k init {TRUE AND';'=';'}} {*}$after]

# ----------------------------------------------------------------------------
# Controls: ticks after an identifier, `all`, a signature, and the tick
# literal
# ----------------------------------------------------------------------------
# band ends in "and" but is an ordinary identifier, so its tick is a
# qualifier: _char_literal_at must answer 0 after it, as it does after any
# identifier, in _find_vhdl_statement_semicolon and _nextw alike.
run_case "case 5: constant c : band := band'('x'), band a subtype of character" \
    [arch_fixture c5_band {
        {  subtype band is character;}
        {  constant c : band := band'('x');}
    }] \
    [list {decl constant c init {band'('x')}} {*}$after]

# Non-regression control: p.all'length, the attribute of a dereferenced
# access value. The tick is not followed by one character and a second
# tick, so _char_literal_at returns 0 on the tick's shape before it looks at
# the word before it.
run_case "case 6: variable n : natural := p.all'length in a process" \
    [arch_fixture c6_all {} {
        {  p_all : process}
        {    variable p : line := new string'("ab");}
        {    variable n : natural := p.all'length;}
        {    variable z : integer := 3;}
        {  begin}
        {    wait;}
        {  end process;}
    } {
        {use std.textio.all;}
    }] \
    [list \
        {pdecl p_all variable p init {new string'("ab")}} \
        {pdecl p_all variable n init {p.all'length}} \
        {pdecl p_all variable z init 3} \
        {process p_all} \
        {*}$after]

# Non-regression control: a user-defined attribute of a function named with
# its signature, f[integer return integer]'att. As in case 6, the tick is
# not followed by one character and a second tick, so _char_literal_at
# returns 0 on the tick's shape before it looks at the prefix.
run_case "case 7: constant k : integer := f\[integer return integer\]'att" \
    [arch_fixture c7_signature {
        {  function f(x : integer) return integer is}
        {  begin}
        {    return x;}
        {  end function;}
        {  attribute att : integer;}
        {  attribute att of f [integer return integer] : function is 3;}
        {  constant k : integer := f[integer return integer]'att;}
    }] \
    [list \
        {decl function f} \
        {decl constant k init {f[integer return integer]'att}} \
        {*}$after]

# ----------------------------------------------------------------------------
# A character literal directly after a reserved word, in a parameter default
# ----------------------------------------------------------------------------
# Decided by _classify_subprogram_header: the tick after `and` opens the
# literal '"', so the header is classified as a body and the procedure's
# `begin` stays the procedure's. Taken for an attribute tick, '"' would open
# a string that never closes, the procedure's `begin` would be taken for the
# architecture's and what follows the procedure would be lost.
run_case "case 8: procedure pr(q : boolean := true and'\"'=c0) is ..." \
    [arch_fixture c8_procedure {
        {  constant c0 : character := '"';}
        {  procedure pr(q : boolean := true and'"'=c0) is}
        {  begin}
        {  end procedure;}
    }] \
    [list \
        {decl constant c0 init {'"'}} \
        {decl procedure pr params {q : boolean := true and'"'=c0}} \
        {*}$after]

# ----------------------------------------------------------------------------
# Control: the tick character literal
# ----------------------------------------------------------------------------
# ''' after a space is a literal: _char_literal_at answers 1 in
# _find_vhdl_statement_semicolon and _nextw alike.
run_case "case 9: constant t : character := '''" \
    [arch_fixture c9_tick {
        {  constant t : character := ''';}
    }] \
    [list {decl constant t init {'''}} {*}$after]

# ----------------------------------------------------------------------------
# A character literal directly after a reserved word, in a process statement
# ----------------------------------------------------------------------------
# Decided by _nextw: _find_end_of_process walks the process word by word
# with _nextw to find its `end`. The tick after `and` opens the literal '"',
# so the walk reaches `end process`. Taken for an attribute tick, '"' would
# open a string that never closes and process p_and would be lost.
run_case "case 10: b := true and'\"'=c0; in a process statement part" \
    [arch_fixture c10_process {
        {  constant c0 : character := '"';}
    } {
        {  p_and : process}
        {    variable b : boolean := false;}
        {  begin}
        {    b := true and'"'=c0;}
        {    wait;}
        {  end process;}
    }] \
    [list \
        {decl constant c0 init {'"'}} \
        {pdecl p_and variable b init false} \
        {*}$after]

# ----------------------------------------------------------------------------
# An extended identifier as qualifier
# ----------------------------------------------------------------------------
# After the '\' that closes an extended identifier, _char_literal_at answers
# 0: the tick is a qualifier tick, in _find_vhdl_statement_semicolon and
# _nextw alike.
#
# Case 11 is a control and does not discriminate: reading '(' as a literal
# would be harmless there, since the scan would resume at x'), no string
# would open and the ';' would still end the declaration. It passes whatever
# the predicate answers after '\'.
run_case "case 11: constant c : \\my type\\ := \\my type\\'('x')" \
    [arch_fixture c11_extended {
        {  subtype \my type\ is character;}
        {  constant c : \my type\ := \my type\'('x');}
    }] \
    [list {decl constant c init {\my type\'('x')}} {*}$after]

# Case 11b discriminates. Decided by _find_vhdl_statement_semicolon: '('
# read as a literal hides the tick after it, the '"' opens a string that
# swallows every later ';', and constant c is lost, as in #71.
run_case "case 11b: constant c : \\my type\\ := \\my type\\'('\"')" \
    [arch_fixture c11b_extended_quote {
        {  subtype \my type\ is character;}
        {  constant c : \my type\ := \my type\'('"');}
    }] \
    [list {decl constant c init {\my type\'('"')}} {*}$after]

} finally {
    cleanup_tmp_files
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "test_char_literal_prefix_word.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
