#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Comment text is returned as written (#38).
#
# Comments containing quotes used to come back with __Qn__ placeholders, both
# in the public `comments` output and in the comments attached to
# declarations. A character literal '"' was paired with the next double quote,
# mangling text that is not a string at all.
#
# Each case is a double-quoted string, a '"' character literal, or both, as a
# full-line comment and as a trailing comment. Placements follow the current
# association rules (not changed here): a procedure takes the line above and
# its trailing comment, a function takes an @brief block above and a short
# trailing comment, and a signal takes a comment two lines above.

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
        puts "FAIL: $label (expected \"$expected\", got \"$got\")"
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
    set dir [file join $base "aurig_core_comment_quotes_[pid]_[clock milliseconds]"]
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

# Fixture builder: append a line, return its 1-based line number.
set ::src {}
proc L {text} {
    lappend ::src $text
    return [llength $::src]
}

# Comment of declaration $name in the first package / architecture, or
# "<none>".
proc decl_comment {decls name} {
    foreach d $decls {
        if {[dict get $d name] eq $name} {
            return [expr {[dict exists $d comment] ? [dict get $d comment] : "<none>"}]
        }
    }
    return "<missing>"
}

# Public comments output at line $n, or "<none>".
proc public_comment {parsed n} {
    if {[dict exists $parsed comments line $n comment]} {
        return [dict get $parsed comments line $n comment]
    }
    return "<none>"
}

# The three comment texts. Each one comes back mangled from the old masking.
set texts [dict create \
    dq   {Returns "ok" when done} \
    cl   {Delimiter '"' then '"' again} \
    both {Writes "done" after '"'}]

set ::tmp_dir [make_tmp_dir]
try {
    set lines [dict create]
    L {library ieee;}
    L {use ieee.std_logic_1164.all;}
    L {}
    L {package q is}
    dict for {key text} $texts {
        L {}
        dict set lines proc_above_$key [L "  -- $text"]
        L "  procedure p_${key}_above(x : integer);"
        L {}
        dict set lines proc_trail_$key [L "  procedure p_${key}_trail(x : integer); -- $text"]
        L {}
        dict set lines func_above_$key [L "  --! @brief $text"]
        L "  function f_${key}_above(x : integer) return integer;"
        L {}
        dict set lines func_trail_$key [L "  function f_${key}_trail(x : integer) return integer; -- $text"]
    }
    # A '"' character literal ahead of a real string: the old masking paired
    # the literal's quote with the string's opening quote.
    L {}
    set pin_text {Quote char '"' precedes "text"}
    dict set lines pin [L "  -- $pin_text"]
    L "  procedure p_pin(x : integer);"
    L {end package q;}
    L {}
    L {entity e is}
    L {  port (clk : in std_logic);}
    L {end entity e;}
    L {}
    L {architecture rtl of e is}
    dict for {key text} $texts {
        L {}
        dict set lines sig_$key [L "  -- $text"]
        L {}
        L "  signal s_${key} : std_logic;"
    }
    L {begin}
    L {  s_dq <= clk;}
    L {end architecture rtl;}

    set parsed [::aurig::core::analyze::vhdlscan \
        -in [tmp_vhd_lines comment_quotes $::src] -verbosity 0]
    set pkg_decls  [dict get [lindex [dict get $parsed packages] 0] declarations]
    set arch_decls [dict get [lindex [dict get $parsed architectures] 0] declarations]

    dict for {key text} $texts {
        # Public comments output, full-line and trailing.
        check_eq "$key: public comment, full-line" \
            [public_comment $parsed [dict get $lines proc_above_$key]] $text
        check_eq "$key: public comment, trailing" \
            [public_comment $parsed [dict get $lines proc_trail_$key]] $text
        # Attached: procedure.
        check_eq "$key: procedure, full-line above" \
            [decl_comment $pkg_decls p_${key}_above] $text
        check_eq "$key: procedure, trailing" \
            [decl_comment $pkg_decls p_${key}_trail] $text
        # Attached: function.
        check_eq "$key: function, @brief block above" \
            [decl_comment $pkg_decls f_${key}_above] "@brief $text"
        check_eq "$key: function, trailing" \
            [decl_comment $pkg_decls f_${key}_trail] $text
        # Attached: signal.
        check_eq "$key: signal, full-line above" \
            [decl_comment $arch_decls s_${key}] $text
    }

    check_eq "character literal ahead of a string: public comment" \
        [public_comment $parsed [dict get $lines pin]] $pin_text
    check_eq "character literal ahead of a string: procedure" \
        [decl_comment $pkg_decls p_pin] $pin_text
} finally {
    cleanup_tmp_files
}

puts ""
puts "Passed: $::pass_count"
puts "Failed: $::fail_count"
exit [expr {$::fail_count > 0}]
