# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#71): a declaration whose initializer holds a qualified
# expression with a character literal, t'('"'), must not be dropped.
#
# Background: _find_vhdl_statement_semicolon recognised a character literal
# by a plain three-character test, so the qualifier tick in character'('"')
# was read as the start of the literal '('. The tick after it was then taken
# as an ordinary character, the '"' opened a string that never closed, no
# terminating ';' was found and the declaration disappeared silently. The scan
# now uses _char_literal_at, the predicate _nextw and
# _classify_subprogram_header share. Constants and signals both reach the
# scan, through _scan_architecture_constants and _scan_architecture_signals.
#
# Positive cases fail on the unpatched parser; controls already parse and
# must stay identical. One case asserts current behaviour that is known to
# be wrong; its comment says why it is asserted anyway.
#
# Every lookup into the parse result is guarded: a missing architecture,
# declaration or field makes the assertion FAIL and the script go on, so a
# run on an unpatched tree reports every case instead of aborting at the
# first missing record.
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
    set dir [file join $base "aurig_core_semicolon_char_literal_[pid]_[clock milliseconds]"]
    file mkdir $dir
    return $dir
}

# Write a fixture from a list of lines. The file is written in binary mode
# so no translation happens on any platform. The path is registered for
# cleanup BEFORE the file is created, and the channel is closed in a finally
# clause, so an error during the write cannot leak either.
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

# Fixture: entity e, architecture rtl whose declarative part is exactly the
# lines $decl, and an empty body.
proc arch_fixture {basename decl} {
    set lines {
        {entity e is}
        {end entity;}
        {architecture rtl of e is}
    }
    lappend lines {*}$decl {begin} {end architecture rtl;}
    return [tmp_vhd_lines $basename $lines]
}

# Sorted "kind:name" of the declarations of the single architecture of
# $path, or "ERROR <reason>" when vhdlscan raises, or "ARCHITECTURES <n>"
# when there is not exactly one. A record without a kind or a name shows as
# "?" in that position, so it fails the comparison instead of raising.
proc decls {path} {
    if {[catch {::aurig::core::analyze::vhdlscan -in $path -verbosity 0} parsed options]} {
        set code [expr {[dict exists $options -errorcode] ? [dict get $options -errorcode] : {}}]
        return [list ERROR [lindex $code 3] $parsed]
    }
    if {![dict exists $parsed architectures]} {
        return [list ARCHITECTURES 0]
    }
    set archs [dict get $parsed architectures]
    if {[llength $archs] != 1} {
        return [list ARCHITECTURES [llength $archs]]
    }
    set arch [lindex $archs 0]
    if {![dict exists $arch declarations]} {
        return [list NO_DECLARATIONS]
    }
    set out {}
    foreach d [dict get $arch declarations] {
        set kind [expr {[dict exists $d kind] ? [dict get $d kind] : "?"}]
        set name [expr {[dict exists $d name] ? [dict get $d name] : "?"}]
        lappend out "$kind:$name"
    }
    return [lsort $out]
}

# Assert the declarations of $path; print what was observed on failure, so a
# run on an unpatched tree documents which declaration was lost. Any error
# raised while checking is itself a FAIL, never an abort.
proc check_decls {label path want} {
    if {[catch {decls $path} got]} {
        puts "FAIL: $label (raised: $got)"
        incr ::fail_count
        return
    }
    set want [lsort $want]
    if {$got eq $want} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (expected $want, got $got)"
        incr ::fail_count
    }
}

set ::tmp_dir [make_tmp_dir]
try {

# ----------------------------------------------------------------------------
# Positive: a qualified expression with a character literal
# ----------------------------------------------------------------------------
check_decls "positive: #71 constant c : character := character'('\"'); then a constant and a signal" \
    [arch_fixture qualified_constant {
        {  constant c : character := character'('"');}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {constant:c constant:m signal:s}

check_decls "positive: the same qualified expression in a signal declaration" \
    [arch_fixture qualified_signal {
        {  signal g : character := character'('"');}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {signal:g constant:m signal:s}

# ----------------------------------------------------------------------------
# Current behaviour, asserted knowingly and NOT endorsed
# ----------------------------------------------------------------------------
# The expected value below is the parser's current WRONG result: constant c
# is lost. It is asserted so that a change in this behaviour is noticed, not
# because it is correct. The comment is not the cause, and this is not the
# #75 route (a '"' earlier on the line hiding `--` from the stripper): the
# comment is stripped cleanly, leaving a line break between the type mark and
# the qualifier tick. _char_literal_at decides from the single character
# before the tick, so after any separator it reads '(' as a literal. The
# second case shows the same loss with a plain space and no comment at all.
check_decls "current, not endorsed: comment between type mark and tick still loses constant c" \
    [arch_fixture qualified_comment_before_tick {
        {  constant c : character := character -- note}
        {    '('"');}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {constant:m signal:s}

check_decls "current, not endorsed: space between type mark and tick still loses constant c" \
    [arch_fixture qualified_space_before_tick {
        {  constant c : character := character '('"');}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {constant:m signal:s}

# ----------------------------------------------------------------------------
# Controls: already parsed and must stay identical
# ----------------------------------------------------------------------------
check_decls "control: ordinary constant with no tick" \
    [arch_fixture ctrl_plain {
        {  constant k : integer := 5;}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {constant:k constant:m signal:s}

check_decls "control: constant whose initializer is a string holding ';'" \
    [arch_fixture ctrl_string {
        {  constant k : string := "x;y";}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {constant:k constant:m signal:s}

check_decls "control: attribute tick after an identifier, t'length" \
    [arch_fixture ctrl_attribute {
        {  constant k : integer := t'length;}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {constant:k constant:m signal:s}

# A character literal '"' directly in an initializer already parsed before
# #71's fix: the tick follows a space, so the plain test read it correctly.
check_decls "control: character literal '\"' directly in an initializer" \
    [arch_fixture ctrl_char_quote {
        {  constant q : character := '"';}
        {  constant m : integer := 1;}
        {  signal s : integer;}
    }] \
    {constant:q constant:m signal:s}

} finally {
    cleanup_tmp_files
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "test_vhdlscan_semicolon_char_literal.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
