# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#49): an architecture whose `begin` is immediately followed by
# its `end` must be parsed, with its declarations, instead of disappearing.
#
# Background: vhdlscan trims every line and joins them with a single "\n", so
# `begin` followed by `end` on the next line leaves exactly one whitespace
# character between them. The architecture regexp required `[\s\n]+` after
# `begin` AND `[\s\n]+` before `end`, i.e. at least two, so it failed to match
# and the line-by-line fallback consumed the architecture without raising
# anything. It survived only when a later `end ...;` in the buffer gave the
# greedy body capture something else to reach, so an empty LAST architecture
# vanished while an empty architecture followed by another unit did not.
#
# Positive cases fail on the unpatched parser; negative cases already parse
# and must stay identical.
#=============================================================================

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set ::pass_count 0
set ::fail_count 0
set ::tmp_files {}
set ::tmp_dir ""

proc check {label cond} {
    if {[uplevel 1 [list expr $cond]]} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label"
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
    set dir [file join $base "aurig_core_empty_arch_body_[pid]_[clock milliseconds]"]
    file mkdir $dir
    return $dir
}

# Write a fixture from a list of lines with the requested line ending.
# eol: lf | crlf. The file is written in binary mode so no translation
# happens on any platform. The path is registered for cleanup BEFORE the
# file is created, and the channel is closed in a finally clause, so an
# error during the write cannot leak either.
proc tmp_vhd_lines {basename lines {eol lf}} {
    set path [file join $::tmp_dir "${basename}.vhd"]
    lappend ::tmp_files $path
    set sep [expr {$eol eq "crlf" ? "\r\n" : "\n"}]
    set fp [open $path w]
    try {
        fconfigure $fp -translation binary
        puts -nonewline $fp "[join $lines $sep]$sep"
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

proc parse {path} {
    return [::aurig::core::analyze::vhdlscan -in $path -verbosity 0]
}

# Architecture $name, or {} if the parser did not emit it.
proc arch_named {parsed name} {
    foreach arch [dict get $parsed architectures] {
        if {[dict get $arch name] eq $name} { return $arch }
    }
    return {}
}

# "kind:name@line" for every declaration of $arch, sorted, or {} if none.
proc decl_summary {arch} {
    if {$arch eq {} || ![dict exists $arch declarations]} { return {} }
    set out {}
    foreach d [dict get $arch declarations] {
        lappend out "[dict get $d kind]:[dict get $d name]@[dict get $d line]"
    }
    return [lsort $out]
}

# Assert that architecture $name of entity $entity exists at $line and
# carries exactly the declarations $decls. Prints what was observed on
# failure, so a run on an unpatched tree documents the disappearance.
proc check_arch {label parsed name entity line decls} {
    set arch [arch_named $parsed $name]
    if {$arch eq {}} {
        puts "FAIL: $label (architecture $name missing; architectures: [llength [dict get $parsed architectures]])"
        incr ::fail_count
        return
    }
    set got [list [dict get $arch entity] [dict get $arch line] [decl_summary $arch]]
    set want [list $entity $line [lsort $decls]]
    if {$got eq $want} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (expected $want, got $got)"
        incr ::fail_count
    }
}

# The fixture header shared by the single-architecture cases: lines 1-5, so
# `begin` is always line 6.
set ::head {
    {entity e is}
    {end entity;}
    {architecture rtl of e is}
    {  type state_t is (IDLE, RUN);}
    {  signal state : state_t;}
}
set ::rtl_decls {type:state_t@4 signal:state@5}

set ::tmp_dir [make_tmp_dir]
try {

# ----------------------------------------------------------------------------
# Positive: one whitespace character between `begin` and `end` after trimming.
# Each fails on the unpatched parser with `architectures {}`.
# ----------------------------------------------------------------------------
foreach eol {lf crlf} {
    set parsed [parse [tmp_vhd_lines "adjacent_$eol" [concat $::head {
        {begin}
        {end architecture rtl;}
    }] $eol]]
    check_arch "positive: begin and end on adjacent lines ($eol)" \
        $parsed rtl e 3 $::rtl_decls
}

set parsed [parse [tmp_vhd_lines "trailing_ws" [concat $::head {
    {begin   	}
    {end architecture rtl;}
}]]]
check_arch "positive: trailing whitespace on the begin line" \
    $parsed rtl e 3 $::rtl_decls

set parsed [parse [tmp_vhd_lines "same_line" [concat $::head {
    {begin end;}
}]]]
check_arch "positive: `begin end;` on one line" $parsed rtl e 3 $::rtl_decls

set parsed [parse [tmp_vhd_lines "end_semi" [concat $::head {
    {begin}
    {end;}
}]]]
check_arch "positive: bare `end;` form" $parsed rtl e 3 $::rtl_decls

set parsed [parse [tmp_vhd_lines "empty_last_of_two" {
    {entity e is}
    {end entity;}
    {architecture a1 of e is}
    {  signal s1 : integer;}
    {begin}
    {  s1 <= 1;}
    {end architecture a1;}
    {architecture a2 of e is}
    {  signal s2 : integer;}
    {begin}
    {end architecture a2;}
}]]
check_arch "positive: empty LAST architecture of two (a2)" \
    $parsed a2 e 8 {signal:s2@9}
check_arch "control: first architecture of the pair (a1) is kept" \
    $parsed a1 e 3 {signal:s1@4}

# ----------------------------------------------------------------------------
# Negative: already parsed before the fix and must stay identical.
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "blank_line" [concat $::head {
    {begin}
    {}
    {end architecture rtl;}
}]]]
check_arch "negative: blank line between begin and end" $parsed rtl e 3 $::rtl_decls

set parsed [parse [tmp_vhd_lines "comment_line" [concat $::head {
    {begin}
    {  -- nothing here yet}
    {end architecture rtl;}
}]]]
check_arch "negative: comment line between begin and end" $parsed rtl e 3 $::rtl_decls

set parsed [parse [tmp_vhd_lines "one_statement" [concat $::head {
    {begin}
    {  state <= IDLE;}
    {end architecture rtl;}
}]]]
check_arch "negative: one statement between begin and end" $parsed rtl e 3 $::rtl_decls

set parsed [parse [tmp_vhd_lines "empty_then_unit" [concat $::head {
    {begin}
    {end architecture rtl;}
    {entity e2 is}
    {end entity;}
}]]]
check_arch "negative: empty body followed by another unit" $parsed rtl e 3 $::rtl_decls
check "negative: the unit after the empty architecture is kept" {
    [lsearch -exact [lmap x [dict get $parsed entities] {dict get $x name}] e2] >= 0
}

set missing_end [file join $aurig_core_root test parser fixtures invalid_syntax missing_end.vhd]
set parsed [parse $missing_end]
check "negative: genuinely unterminated architecture (missing_end.vhd) still yields none" {
    [llength [dict get $parsed architectures]] == 0
}

# ----------------------------------------------------------------------------
# Regexp contract: `begin` keeps its word boundary, and the caller's five
# bindings (whole match, name, entity, declarative part, body) are unchanged.
# ----------------------------------------------------------------------------
set re $::aurig::core::util::re::re_architecture
check "regexp: `begin_cnt` is not accepted as the begin keyword" {
    ![regexp -nocase -- $re "architecture rtl of e is\nbegin_cnt\nend;\n"]
}
set m [regexp -nocase -inline -- $re \
    "architecture rtl of e is\nsignal s : integer;\nbegin\ns <= 1;\nend architecture rtl;\n"]
check "regexp: name, entity, declarative part and body keep their group numbers" {
    [lindex $m 2] eq "rtl" && [lindex $m 3] eq "e" &&
    [string trim [lindex $m 4]] eq "signal s : integer;" &&
    [string trim [lindex $m 5]] eq "s <= 1;"
}

} finally {
    cleanup_tmp_files
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "test_vhdlscan_empty_architecture_body.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
