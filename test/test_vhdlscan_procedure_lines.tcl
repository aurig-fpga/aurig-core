# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#29): procedure declarations and bodies must report the line
# of their `procedure` keyword, in package declarations, package bodies and
# architecture declarative parts, and a comment on the line immediately above
# a procedure must be attached to it.
#
# Background: _scan_procedures computed the line as $n plus the newlines
# before the procedure name plus one, while _scan_functions uses
# _index_to_line ($n plus the newlines). Every procedure was reported one
# line late, and the comment scan, which starts one line above the reported
# line, looked at the procedure's own line and never found the comment
# immediately above it.
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

# Comment assertion that prints the observed comment on failure.
proc check_comment {label got expected} {
    if {$got eq $expected} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (expected comment \"$expected\", got \"$got\")"
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
    set dir [file join $base "aurig_core_procedure_lines_[pid]_[clock milliseconds]"]
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

# Return the first item named $name in $items, or {} if there is none.
proc find_named {items name} {
    foreach item $items {
        if {[dict get $item name] eq $name} { return $item }
    }
    return {}
}

# Declaration $name in the first package declaration.
proc pkg_decl {parsed name} {
    set pkg [lindex [dict get $parsed packages] 0]
    return [find_named [dict get $pkg declarations] $name]
}

# Subprogram $name (key: procedures|functions) in the first package body.
proc pkg_body_item {parsed key name} {
    set body [lindex [dict get $parsed package_bodies] 0]
    if {![dict exists $body $key]} { return {} }
    return [find_named [dict get $body $key] $name]
}

# Declaration $name in the first architecture.
proc arch_decl {parsed name} {
    set arch [lindex [dict get $parsed architectures] 0]
    return [find_named [dict get $arch declarations] $name]
}

proc line_of {item} {
    return [expr {[dict exists $item line] ? [dict get $item line] : -1}]
}

proc comment_of {item} {
    return [expr {[dict exists $item comment] ? [dict get $item comment] : ""}]
}

# Every fixture is created and parsed inside this try block; the finally
# clause removes the per-run directory even when a case raises a Tcl error.
set ::tmp_dir [make_tmp_dir]
try {

# ----------------------------------------------------------------------------
# Case 1: minimal reproduction from the issue, LF and CRLF
# ----------------------------------------------------------------------------
foreach eol {lf crlf} {
    set parsed [parse [tmp_vhd_lines "minimal_$eol" {
        {package p is}
        {  procedure show(s : string);}
        {end package;}
    } $eol]]
    check_line "minimal ($eol): procedure show in package declaration" \
        [line_of [pkg_decl $parsed show]] 2
}

# ----------------------------------------------------------------------------
# Case 2: package declaration and package body, with function controls
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "package_body" {
    {package p is}
    {  procedure show(s : string);}
    {  function f(x : integer) return integer;}
    {end package;}
    {package body p is}
    {  function f(x : integer) return integer is}
    {  begin}
    {    return x;}
    {  end function;}
    {  procedure show(s : string) is}
    {    variable v : integer;}
    {  begin}
    {  end procedure;}
    {  procedure reset is}
    {  begin}
    {  end procedure;}
    {end package body;}
}]]
check_line "package declaration: procedure show" [line_of [pkg_decl $parsed show]] 2
check_line "package body: procedure show" [line_of [pkg_body_item $parsed procedures show]] 10
check_line "package body: parameterless procedure reset" \
    [line_of [pkg_body_item $parsed procedures reset]] 14
check_line "control, package declaration: function f" [line_of [pkg_decl $parsed f]] 3
check_line "control, package body: function f" [line_of [pkg_body_item $parsed functions f]] 6

# ----------------------------------------------------------------------------
# Case 3: architecture declarative part, with function and signal controls
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "architecture" {
    {entity e is end entity;}
    {architecture rtl of e is}
    {  signal a : bit;}
    {  procedure pa(x : in bit) is}
    {  begin}
    {  end procedure;}
    {  function fa(x : bit) return bit is}
    {  begin}
    {    return x;}
    {  end function;}
    {begin}
    {end architecture;}
}]]
check_line "architecture: procedure pa" [line_of [arch_decl $parsed pa]] 4
check_line "control, architecture: function fa" [line_of [arch_decl $parsed fa]] 7
check_line "control, architecture: signal a" [line_of [arch_decl $parsed a]] 3

# ----------------------------------------------------------------------------
# Case 4: a comment on the line immediately above a procedure is attached
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "comment_architecture" {
    {entity e is end entity;}
    {architecture rtl of e is}
    {  signal a : bit;}
    {  -- Procedure declared in architecture}
    {  procedure pa(x : in bit) is}
    {  begin}
    {  end procedure;}
    {begin}
    {end architecture;}
}]]
check_line "comment layout, architecture: procedure pa" [line_of [arch_decl $parsed pa]] 5
check_comment "comment layout, architecture: comment attached to pa" \
    [comment_of [arch_decl $parsed pa]] "Procedure declared in architecture"

set parsed [parse [tmp_vhd_lines "comment_package_body" {
    {package p is}
    {  procedure show(s : string);}
    {end package;}
    {package body p is}
    {  -- Shows a string}
    {  procedure show(s : string) is}
    {  begin}
    {  end procedure;}
    {end package body;}
}]]
check_line "comment layout, package body: procedure show" \
    [line_of [pkg_body_item $parsed procedures show]] 6
check_comment "comment layout, package body: comment attached to show" \
    [comment_of [pkg_body_item $parsed procedures show]] "Shows a string"

# ----------------------------------------------------------------------------
# Case 5: parameters spread over several lines report the line of the
# `procedure` keyword, not a line inside or after the parameter list
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "multiline_params" {
    {package p is}
    {  procedure configure(}
    {    signal clk : in bit;}
    {    constant n : in integer}
    {  );}
    {end package;}
    {package body p is}
    {  procedure configure(}
    {    signal clk : in bit;}
    {    constant n : in integer}
    {  ) is}
    {  begin}
    {  end procedure;}
    {end package body;}
}]]
check_line "multi-line parameters, package declaration: procedure configure" \
    [line_of [pkg_decl $parsed configure]] 2
check_line "multi-line parameters, package body: procedure configure" \
    [line_of [pkg_body_item $parsed procedures configure]] 8

# ----------------------------------------------------------------------------
# Case 6: a trailing comment on the procedure's own line is attached; with a
# comment above as well, both are attached, the comment above first
# ----------------------------------------------------------------------------
set parsed [parse [tmp_vhd_lines "inline_package" {
    {package p is}
    {  procedure reset(signal rst : out bit); -- Active high reset}
    {}
    {  -- Reset procedure}
    {  procedure clear(signal rst : out bit); -- Clears the register}
    {end package;}
    {package body p is}
    {  procedure reset(signal rst : out bit) is -- Drives rst high}
    {  begin}
    {  end procedure;}
    {  -- Clear implementation}
    {  procedure clear(signal rst : out bit) is -- Drives rst low}
    {  begin}
    {  end procedure;}
    {end package body;}
}]]
check_comment "inline only, package declaration: comment attached to reset" \
    [comment_of [pkg_decl $parsed reset]] "Active high reset"
check_comment "above and inline, package declaration: both attached to clear" \
    [comment_of [pkg_decl $parsed clear]] "Reset procedure\nClears the register"
check_comment "inline only, package body: comment attached to reset" \
    [comment_of [pkg_body_item $parsed procedures reset]] "Drives rst high"
check_comment "above and inline, package body: both attached to clear" \
    [comment_of [pkg_body_item $parsed procedures clear]] "Clear implementation\nDrives rst low"

set parsed [parse [tmp_vhd_lines "inline_architecture" {
    {entity e is end entity;}
    {architecture rtl of e is}
    {  procedure pa(x : in bit) is -- Inline only}
    {  begin}
    {  end procedure;}
    {  -- Above}
    {  procedure pb(x : in bit) is -- Inline}
    {  begin}
    {  end procedure;}
    {begin}
    {end architecture;}
}]]
check_comment "inline only, architecture: comment attached to pa" \
    [comment_of [arch_decl $parsed pa]] "Inline only"
check_comment "above and inline, architecture: both attached to pb" \
    [comment_of [arch_decl $parsed pb]] "Above\nInline"

# Controls: function comment behaviour is unchanged. A block above without
# @brief yields to the inline comment; a block with @brief wins; an inline
# comment alone is attached.
set parsed [parse [tmp_vhd_lines "inline_function_control" {
    {package p is}
    {  function inc(a : integer) return integer; -- Increment}
    {  -- Adds one}
    {  function add(a : integer) return integer; -- Sum}
    {  -- @brief Negates a value}
    {  function neg(a : integer) return integer; -- Negation}
    {end package;}
}]]
check_comment "control, function with inline comment only" \
    [comment_of [pkg_decl $parsed inc]] "Increment"
check_comment "control, function with block above (no @brief) and inline" \
    [comment_of [pkg_decl $parsed add]] "Sum"
check_comment "control, function with @brief block above and inline" \
    [comment_of [pkg_decl $parsed neg]] "@brief Negates a value"

} finally {
    cleanup_tmp_files
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "test_vhdlscan_procedure_lines.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
