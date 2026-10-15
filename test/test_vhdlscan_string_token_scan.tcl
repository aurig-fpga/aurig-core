# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#34): a keyword inside a string literal must not be taken for a
# keyword by the token scan that splits an architecture, finds the end of a
# process, or finds the `begin` of a subprogram.
#
# Background: _nextw skipped every non-letter character, the double quote
# included, so it returned the words inside a string as tokens. A string
# containing `begin` or `generate` raised UNBALANCED_END; a string containing
# `end` in the architecture body closed the architecture at the string and
# silently dropped everything after it. The `--` in the original report is
# irrelevant: comments are stripped before this point, and "hello begin
# still text" fails the same way.
#
# Out of scope: the keyword-finding regexps of _scan_processes and of the
# declaration and instantiation scanners do not see strings either (phantom
# declarations). That is a separate class and is not asserted here.
#
# Positive cases fail on the unpatched parser; controls already parse and
# must stay identical.
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
    set dir [file join $base "aurig_core_string_token_scan_[pid]_[clock milliseconds]"]
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

# Fixture: entity e, architecture rtl with signal s, the extra declarative
# lines $decl, signal s_last, `begin`, the extra body lines $body, then
# process p_main, whose body is `s_last <= s;`.
proc arch_fixture {basename decl body} {
    set lines {
        {entity e is}
        {end entity;}
        {architecture rtl of e is}
        {  signal s : integer;}
    }
    lappend lines {*}$decl {  signal s_last : integer;} {begin} {*}$body
    lappend lines \
        {  p_main : process(s)} \
        {  begin} \
        {    s_last <= s;} \
        {  end process p_main;} \
        {end architecture rtl;}
    return [tmp_vhd_lines $basename $lines]
}

# Summary of the single architecture of $path:
#   decls: sorted "kind:name" of its declarations
#   procs: "label=body" of its processes, in order
# or "ERROR <reason>" when vhdlscan raises.
proc summary {path} {
    if {[catch {::aurig::core::analyze::vhdlscan -in $path -verbosity 0} parsed options]} {
        return [list ERROR [lindex [dict get $options -errorcode] 3]]
    }
    set archs [dict get $parsed architectures]
    if {[llength $archs] != 1} {
        return [list ARCHITECTURES [llength $archs]]
    }
    set arch [lindex $archs 0]
    set decls {}
    foreach d [dict get $arch declarations] {
        set item "[dict get $d kind]:[dict get $d name]"
        if {[dict exists $d body_declarations]} {
            append item "([llength [dict get $d body_declarations]])"
        }
        lappend decls $item
    }
    set procs {}
    foreach p [dict get $arch processes] {
        lappend procs "[dict get $p label]=[string map {"\n" " "} [dict get $p body]]"
    }
    return [list decls [lsort $decls] procs $procs]
}

# Assert the summary of $path; print what was observed on failure, so a run
# on an unpatched tree documents the error or the truncation.
proc check_summary {label path decls procs} {
    set got [summary $path]
    set want [list decls [lsort $decls] procs $procs]
    if {$got eq $want} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (expected $want, got $got)"
        incr ::fail_count
    }
}

set ::base_decls {signal:s signal:s_last}
set ::p_main {{p_main=s_last <= s;}}

set ::tmp_dir [make_tmp_dir]
try {

# ----------------------------------------------------------------------------
# Positive: keywords inside strings in the architecture declarative part
# ----------------------------------------------------------------------------
check_summary "positive: \"... begin ...\" in the declarative part" \
    [arch_fixture decl_begin {{  constant m : string := "hello begin still text";}} {}] \
    [list {*}$::base_decls constant:m] $::p_main

check_summary "positive: \"... -- begin ...\" from the issue, in the declarative part" \
    [arch_fixture decl_dash_begin {{  constant m : string := "hello -- begin still text";}} {}] \
    [list {*}$::base_decls constant:m] $::p_main

# ----------------------------------------------------------------------------
# Positive: keywords inside strings in the architecture body
# ----------------------------------------------------------------------------
check_summary "positive: \"... begin ...\" in the body" \
    [arch_fixture body_begin {} {{  assert s = 0 report "x begin y" severity note;}}] \
    $::base_decls $::p_main

check_summary "positive: \"... generate ...\" in the body" \
    [arch_fixture body_generate {} {{  assert s = 0 report "x generate y" severity note;}}] \
    $::base_decls $::p_main

# Previously SILENT: the architecture body was closed at the string and the
# following process disappeared without any error.
check_summary "positive (was silent): \"... end ...\" in the body keeps the following process" \
    [arch_fixture body_end {} {{  assert s = 0 report "x end y" severity note;}}] \
    $::base_decls $::p_main

check_summary "positive (was silent): \"end;\" in the body keeps the following process" \
    [arch_fixture body_end_semi {} {{  assert s = 0 report "end;" severity note;}}] \
    $::base_decls $::p_main

# Inside a process: the process body used to be cut at the string, and the
# next process was lost with it.
check_summary "positive: \"end;\" inside a process keeps its body and the next process" \
    [arch_fixture in_process_end_semi {} {
        {  p_first : process(s)}
        {  begin}
        {    report "end;";}
        {  end process p_first;}
    }] \
    $::base_decls [list {p_first=report "end;";} {*}$::p_main]

# ----------------------------------------------------------------------------
# Positive: keywords inside strings in a subprogram of the declarative part
# ----------------------------------------------------------------------------
check_summary "positive: \"... begin ...\" inside a subprogram body" \
    [arch_fixture subprogram_begin {
        {  procedure pp is}
        {  begin}
        {    report "x begin y";}
        {  end procedure pp;}
    } {}] \
    [list {*}$::base_decls procedure:pp] $::p_main

check_summary "positive: \"procedure ...\" in a subprogram's declarations keeps body_declarations" \
    [arch_fixture subprogram_decl_keyword {
        {  procedure pp is}
        {    constant msg : string := "procedure inside string";}
        {  begin}
        {  end procedure pp;}
    } {}] \
    [list {*}$::base_decls {procedure:pp(1)}] $::p_main

# ----------------------------------------------------------------------------
# Positive: literal forms that must not shift string parity
# ----------------------------------------------------------------------------
check_summary "positive: doubled quote \"a\"\"begin\"\"b\"" \
    [arch_fixture doubled_quote {{  constant m : string := "a""begin""b";}} {}] \
    [list {*}$::base_decls constant:m] $::p_main

check_summary "positive: \"\"\"\" followed by a keyword string" \
    [arch_fixture quote_only {
        {  constant q : string := """";}
        {  constant m : string := "x begin y";}
    } {}] \
    [list {*}$::base_decls constant:q constant:m] $::p_main

check_summary "positive: bit-strings X\"FF\" and B\"1010\" beside a keyword string" \
    [arch_fixture bit_strings {
        {  constant v1 : bit_vector(7 downto 0) := X"FF";}
        {  constant v2 : bit_vector(3 downto 0) := B"1010";}
        {  constant m : string := "x begin y";}
    } {}] \
    [list {*}$::base_decls constant:v1 constant:v2 constant:m] $::p_main

check_summary "positive: character literal '\"' followed by a keyword string" \
    [arch_fixture char_quote_then_string {
        {  constant c : character := '"';}
        {  constant m : string := "x begin y";}
    } {}] \
    [list {*}$::base_decls constant:c constant:m] $::p_main

# t'('"'): the tick after `character` is a qualifier, not the start of a
# character literal; reading `'('` as a literal would open a string on the
# following double quote. Only the split is asserted: constant c itself is
# lost by _find_vhdl_statement_semicolon, which has the plain three-character
# tick test and drops it even without any keyword string (pre-existing, not
# part of this change), so the full declaration list is not asserted here.
set got [summary [arch_fixture qualified_char_quote {
    {  constant c : character := character'('"');}
    {  constant m : string := "x begin y";}
} {}]]
if {[lindex $got 0] eq "decls" &&
    "constant:m" in [dict get $got decls] &&
    [dict get $got procs] eq $::p_main} {
    puts "PASS: positive: qualified expression character'('\"') followed by a keyword string"
    incr ::pass_count
} else {
    puts "FAIL: positive: qualified expression character'('\"') followed by a keyword string (expected constant:m and $::p_main, got $got)"
    incr ::fail_count
}

# ----------------------------------------------------------------------------
# Controls: already parsed and must stay identical
# ----------------------------------------------------------------------------
check_summary "control: \"... -- ...\" without a keyword" \
    [arch_fixture ctrl_dash {{  constant m : string := "hello -- still text";}} {}] \
    [list {*}$::base_decls constant:m] $::p_main

check_summary "control: \"... generate ...\" in the declarative part" \
    [arch_fixture ctrl_decl_generate {{  constant m : string := "x generate y";}} {}] \
    [list {*}$::base_decls constant:m] $::p_main

check_summary "control: character literal '\"' alone" \
    [arch_fixture ctrl_char_quote {{  constant c : character := '"';}} {}] \
    [list {*}$::base_decls constant:c] $::p_main

check_summary "control: identifiers end_flag and begin_cnt" \
    [arch_fixture ctrl_identifiers {
        {  signal end_flag : integer;}
        {  signal begin_cnt : integer;}
    } {}] \
    [list {*}$::base_decls signal:end_flag signal:begin_cnt] $::p_main

check_summary "control: bit-strings X\"FF\" and B\"1010\" alone" \
    [arch_fixture ctrl_bit_strings {
        {  constant v1 : bit_vector(7 downto 0) := X"FF";}
        {  constant v2 : bit_vector(3 downto 0) := B"1010";}
    } {}] \
    [list {*}$::base_decls constant:v1 constant:v2] $::p_main

} finally {
    cleanup_tmp_files
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "test_vhdlscan_string_token_scan.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
