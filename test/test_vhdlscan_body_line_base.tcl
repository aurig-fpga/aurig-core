# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#23): line numbers of architecture-body constructs must not
# shift when the declarative part ends with blank, comment-only or
# whitespace-only lines immediately before `begin`.
#
# Background: split_arch_decl_body returns the declarative part trimmed, and
# parse_architecture derived the body line base from the newline count of
# that trimmed text plus one. The "+1" compensates for exactly one trimmed
# newline, so every additional empty line before `begin` moved every body
# line (processes, process-local declarations, instantiations, generates)
# one line too early and made the process/instantiation comment lookup miss
# the comment that is present. The parse buffer is comment-stripped and
# trimmed line by line, so comment-only and whitespace-only lines behave
# exactly like blank lines.
#
# Every fixture below is written with explicit line endings so the asserted
# line numbers are the physical lines of the file.
#=============================================================================

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set ::pass_count 0
set ::fail_count 0
set ::tmp_files {}

proc check {label cond} {
    if {[uplevel 1 [list expr $cond]]} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label"
        incr ::fail_count
    }
}

# Line assertion that prints the observed value on failure, so a run on an
# unpatched tree documents the wrong line it reported.
proc check_line {label got expected} {
    if {$got == $expected} {
        puts "PASS: $label (line $expected)"
        incr ::pass_count
    } else {
        puts "FAIL: $label (expected line $expected, got $got)"
        incr ::fail_count
    }
}

# Write a fixture from a list of lines with the requested line ending.
# eol: lf | crlf. The file is written in binary mode so no translation
# happens on any platform.
proc tmp_vhd_lines {basename lines {eol lf}} {
    set path [file join [file dirname [info script]] "_tmp_${basename}.vhd"]
    set sep [expr {$eol eq "crlf" ? "\r\n" : "\n"}]
    set fp [open $path w]
    fconfigure $fp -translation binary
    puts -nonewline $fp "[join $lines $sep]$sep"
    close $fp
    lappend ::tmp_files $path
    return $path
}

proc cleanup_tmp_files {} {
    foreach path $::tmp_files {
        catch {file delete -- $path}
    }
}

proc parse {path} {
    return [::aurig::core::analyze::vhdlscan -in $path -verbosity 0]
}

proc arch0 {parsed} {
    return [lindex [dict get $parsed architectures] 0]
}

# Return the first item of $key (processes|instantiations|generates) in the
# first architecture whose label equals $label ("" for an unlabelled item).
proc body_item {parsed key label} {
    set arch [arch0 $parsed]
    if {![dict exists $arch $key]} { return {} }
    foreach item [dict get $arch $key] {
        set l [expr {[dict exists $item label] ? [dict get $item label] : ""}]
        if {$l eq $label} { return $item }
    }
    return {}
}

proc item_line {parsed key label} {
    set item [body_item $parsed $key $label]
    return [expr {[dict exists $item line] ? [dict get $item line] : -1}]
}

proc item_comment {parsed key label} {
    set item [body_item $parsed $key $label]
    return [expr {[dict exists $item comment] ? [dict get $item comment] : ""}]
}

proc decl_line {parsed name} {
    foreach d [dict get [arch0 $parsed] declarations] {
        if {[dict get $d name] eq $name} { return [dict get $d line] }
    }
    return -1
}

proc process_decl_line {parsed label name} {
    set p [body_item $parsed processes $label]
    if {![dict exists $p declarations]} { return -1 }
    foreach d [dict get $p declarations] {
        if {[dict get $d name] eq $name} { return [dict get $d line] }
    }
    return -1
}

# ----------------------------------------------------------------------------
# Fixture texts (one list element per physical line)
# ----------------------------------------------------------------------------
set minimal {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {}
    {begin}
    {p: process begin wait; end process;}
    {end architecture;}
}

set paired {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {signal a: bit;}
    {}
    {begin}
    {p: process begin wait; end process;}
    {u: entity work.child port map(a=>a);}
    {end architecture;}
}

# ----------------------------------------------------------------------------
# Case 1: minimal reproduction from the issue, LF and CRLF
# ----------------------------------------------------------------------------
foreach eol {lf crlf} {
    set parsed [parse [tmp_vhd_lines "minimal_$eol" $minimal $eol]]
    check_line "minimal ($eol): process p" [item_line $parsed processes p] 5
}

# ----------------------------------------------------------------------------
# Case 2: paired process/instantiation fixture, LF and CRLF
# ----------------------------------------------------------------------------
foreach eol {lf crlf} {
    set parsed [parse [tmp_vhd_lines "paired_$eol" $paired $eol]]
    check_line "paired ($eol): architecture-level signal a (declarative part, control)" [decl_line $parsed a] 3
    check_line "paired ($eol): process p" [item_line $parsed processes p] 6
    check_line "paired ($eol): instance u" [item_line $parsed instantiations u] 7
}

# ----------------------------------------------------------------------------
# Case 3: two blank lines before begin
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "two_blank" {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {}
    {}
    {begin}
    {p: process begin wait; end process;}
    {u: entity work.child port map(a=>a);}
    {end architecture;}
}]]
check_line "two blank lines before begin: process p" [item_line $parsed processes p] 6
check_line "two blank lines before begin: instance u" [item_line $parsed instantiations u] 7

# ----------------------------------------------------------------------------
# Case 4: comment-only line before begin
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "comment_only" {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {-- comment-only line in the declarative tail}
    {begin}
    {p: process begin wait; end process;}
    {u: entity work.child port map(a=>a);}
    {end architecture;}
}]]
check_line "comment-only line before begin: process p" [item_line $parsed processes p] 5
check_line "comment-only line before begin: instance u" [item_line $parsed instantiations u] 6

# ----------------------------------------------------------------------------
# Case 5: whitespace-only lines before begin (tab, spaces), LF and CRLF
# ----------------------------------------------------------------------------
foreach eol {lf crlf} {
    set parsed [parse [tmp_vhd_lines "tab_only_$eol" [list \
        {entity sample is end entity;} \
        {architecture rtl of sample is} \
        "\t" \
        {begin} \
        {p: process begin wait; end process;} \
        {end architecture;}] $eol]]
    check_line "tab-only line before begin ($eol): process p" [item_line $parsed processes p] 5

    set parsed [parse [tmp_vhd_lines "spaces_only_$eol" [list \
        {entity sample is end entity;} \
        {architecture rtl of sample is} \
        "    " \
        {begin} \
        {p: process begin wait; end process;} \
        {end architecture;}] $eol]]
    check_line "spaces-only line before begin ($eol): process p" [item_line $parsed processes p] 5
}

# ----------------------------------------------------------------------------
# Case 6: comment attachment in the blank-line layout. The scanner looks up
# the comment two lines above the construct (a blank line between them), so
# the fixture uses that distance; the same layout attaches in the control.
# ----------------------------------------------------------------------------
set with_comments {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {signal a: bit;}
    {}
    {begin}
    {-- Process comment that must stay attached}
    {}
    {p: process begin wait; end process;}
    {-- Instance comment that must stay attached}
    {}
    {u: entity work.child port map(a=>a);}
    {end architecture;}
}
set parsed [parse [tmp_vhd_lines "comment_attach" $with_comments]]
check_line "comment attachment layout: process p" [item_line $parsed processes p] 8
check "comment attachment layout: process comment attached" \
    {[item_comment $parsed processes p] eq "Process comment that must stay attached"}
check_line "comment attachment layout: instance u" [item_line $parsed instantiations u] 11
check "comment attachment layout: instance comment attached" \
    {[item_comment $parsed instantiations u] eq "Instance comment that must stay attached"}

# ----------------------------------------------------------------------------
# Case 7: generate and block statements, with process-local declarations
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "generate_block" {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {signal a: bit;}
    {}
    {begin}
    {g: if true generate}
    {  u: entity work.child port map(a=>a);}
    {end generate g;}
    {b: block}
    {begin}
    {  p: process}
    {    variable v: integer;}
    {    constant c: integer := 1;}
    {  begin}
    {    wait;}
    {  end process p;}
    {end block b;}
    {end architecture;}
}]]
check_line "generate g" [item_line $parsed generates g] 6
check_line "instance u inside the generate" [item_line $parsed instantiations u] 7
check_line "process p inside the block" [item_line $parsed processes p] 11
check_line "process-local variable v" [process_decl_line $parsed p v] 12
check_line "process-local constant c" [process_decl_line $parsed p c] 13

# ----------------------------------------------------------------------------
# Controls (must pass before and after the fix)
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "ctl_no_extra_line" {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {signal a: bit;}
    {begin}
    {p: process begin wait; end process;}
    {u: entity work.child port map(a=>a);}
    {end architecture;}
}]]
check_line "control, no extra line before begin: process p" [item_line $parsed processes p] 5
check_line "control, no extra line before begin: instance u" [item_line $parsed instantiations u] 6

set parsed [parse [tmp_vhd_lines "ctl_after_begin" {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {begin}
    {}
    {-- comment after begin}
    {p: process begin wait; end process;}
    {u: entity work.child port map(a=>a);}
    {end architecture;}
}]]
check_line "control, blank and comment lines after begin: process p" [item_line $parsed processes p] 6
check_line "control, blank and comment lines after begin: instance u" [item_line $parsed instantiations u] 7

set parsed [parse [tmp_vhd_lines "ctl_comment_attach" {
    {entity sample is end entity;}
    {architecture rtl of sample is}
    {signal a: bit;}
    {begin}
    {-- Process comment in the control layout}
    {}
    {p: process begin wait; end process;}
    {end architecture;}
}]]
check_line "control, comment attachment layout: process p" [item_line $parsed processes p] 7
check "control, comment attachment layout: process comment attached" \
    {[item_comment $parsed processes p] eq "Process comment in the control layout"}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
cleanup_tmp_files
puts ""
puts "============================================================"
puts "test_vhdlscan_body_line_base.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
