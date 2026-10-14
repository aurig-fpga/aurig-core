#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Types and subprograms declared in a process declarative part (#24, #48).
#
# _scan_processes surfaced only process-local variables and constants. Types,
# subtypes, functions and procedures are now returned under the process too,
# keeping the records their scanners return (subtype_kind / literals; return,
# params, purity, comment, body_declarations), at their source lines.
#
# Controls: the variable / constant records keep their exact shape, a local of
# a process-local function does not surface as a process variable, and the
# process line and label do not move.

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
    set dir [file join $base "aurig_core_process_declarations_[pid]_[clock milliseconds]"]
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

proc parse {path} {
    return [::aurig::core::analyze::vhdlscan -in $path -verbosity 0]
}

# Process labelled $label in the first architecture, or {}.
proc process_named {parsed label} {
    set arch [lindex [dict get $parsed architectures] 0]
    foreach p [dict get $arch processes] {
        if {[dict get $p label] eq $label} { return $p }
    }
    return {}
}

# Declaration $name of process $proc, or {}.
proc proc_decl {proc name} {
    if {![dict exists $proc declarations]} { return {} }
    foreach d [dict get $proc declarations] {
        if {[dict get $d name] eq $name} { return $d }
    }
    return {}
}

# Field $key of $d, or "<absent>".
proc field {d key} {
    if {[dict exists $d $key]} { return [dict get $d $key] }
    return "<absent>"
}

# Names / lines of a literals list, or "<absent>".
proc literal_names {d} {
    if {![dict exists $d literals]} { return "<absent>" }
    set out {}
    foreach l [dict get $d literals] { lappend out [dict get $l name] }
    return $out
}
proc literal_lines {d} {
    if {![dict exists $d literals]} { return "<absent>" }
    set out {}
    foreach l [dict get $d literals] { lappend out [dict get $l line] }
    return $out
}

set ::tmp_dir [make_tmp_dir]
try {
    # Line numbers are part of the assertions: keep this layout in step.
    set main_src [tmp_vhd_lines process_decls {
        {library ieee;}
        {use ieee.std_logic_1164.all;}
        {}
        {entity p is}
        {  port (clk : in std_logic);}
        {end entity p;}
        {}
        {architecture rtl of p is}
        {  signal s : std_logic;}
        {}
        {  -- trailing blank and comment lines in the arch decl tail (#23)}
        {}
        {begin}
        {}
        {  -- Main process comment here}
        {  main : process (clk) is}
        {    type proc_state_t is (P_IDLE, P_RUN);}
        {    subtype small_t is integer range 0 to 7;}
        {    variable v_cnt : integer := 0;}
        {    constant C_MAX : integer := 7;}
        {}
        {    -- Local function doc comment}
        {    function f_inc(x : integer) return integer is}
        {      variable tmp : integer;}
        {    begin}
        {      return x + 1;}
        {    end function;}
        {}
        {    -- Local procedure doc comment}
        {    procedure p_reset(signal q : out std_logic) is}
        {    begin}
        {      q <= '0';}
        {    end procedure;}
        {  begin}
        {    if rising_edge(clk) then}
        {      v_cnt := f_inc(v_cnt);}
        {    end if;}
        {  end process main;}
        {}
        {  other : process}
        {    procedure p_bare is}
        {    begin}
        {      null;}
        {    end procedure;}
        {  begin}
        {    wait;}
        {  end process;}
        {end architecture rtl;}
    }]
    set gen_src [tmp_vhd_lines process_decls_generate {
        {library ieee;}
        {use ieee.std_logic_1164.all;}
        {entity g is}
        {  port (clk : in std_logic);}
        {end entity g;}
        {architecture rtl of g is}
        {begin}
        {  gen : for i in 0 to 1 generate}
        {    inner : process (clk)}
        {      type gen_state_t is (G_A, G_B);}
        {      variable v_x : integer;}
        {    begin}
        {    end process inner;}
        {  end generate gen;}
        {end architecture rtl;}
    }]

    set parsed [parse $main_src]
    set main  [process_named $parsed main]
    set other [process_named $parsed other]
    set gparsed [parse $gen_src]
    set inner [process_named $gparsed inner]

    # --- Types (#48) ---------------------------------------------------------
    set t [proc_decl $main proc_state_t]
    check_eq "type: proc_state_t is returned as kind type" [field $t kind] type
    check_eq "type: proc_state_t line" [field $t line] 17
    check_eq "type: proc_state_t keeps subtype_kind" [field $t subtype_kind] enumerated
    check_eq "type: proc_state_t keeps literal names" [literal_names $t] {P_IDLE P_RUN}
    check_eq "type: proc_state_t literal lines" [literal_lines $t] {17 17}

    set st [proc_decl $main small_t]
    check_eq "subtype: small_t is returned as kind subtype" [field $st kind] subtype
    check_eq "subtype: small_t line" [field $st line] 18

    set gt [proc_decl $inner gen_state_t]
    check_eq "generate: gen_state_t is returned as kind type" [field $gt kind] type
    check_eq "generate: gen_state_t line" [field $gt line] 10
    check_eq "generate: gen_state_t keeps literal names" [literal_names $gt] {G_A G_B}

    # --- Subprograms (#24) ---------------------------------------------------
    set f [proc_decl $main f_inc]
    check_eq "function: f_inc is returned as kind function" [field $f kind] function
    check_eq "function: f_inc line" [field $f line] 23
    check_eq "function: f_inc keeps return" [field $f return] integer
    check_eq "function: f_inc keeps purity" [field $f purity] pure
    check_eq "function: f_inc keeps params" [field $f params] {x : integer}
    set bd_names {}
    foreach b [expr {[dict exists $f body_declarations] ? [dict get $f body_declarations] : {}}] {
        lappend bd_names "[dict get $b kind]:[dict get $b name]@[dict get $b line]"
    }
    check_eq "function: f_inc keeps body_declarations" $bd_names {variable:tmp@24}

    set p [proc_decl $main p_reset]
    check_eq "procedure: p_reset is returned as kind procedure" [field $p kind] procedure
    check_eq "procedure: p_reset line" [field $p line] 30
    check_eq "procedure: p_reset keeps params" [field $p params] {signal q : out std_logic}
    check_eq "procedure: p_reset comment (commentDict passed through)" \
        [field $p comment] {Local procedure doc comment}

    set pb [proc_decl $other p_bare]
    check_eq "procedure: p_bare in a process without 'is' is returned" [field $pb kind] procedure
    check_eq "procedure: p_bare line" [field $pb line] 41

    # --- Controls: must hold before and after --------------------------------
    check_eq "control: v_cnt record unchanged" [proc_decl $main v_cnt] \
        {kind variable name v_cnt type integer init 0 line 19}
    check_eq "control: C_MAX record unchanged" [proc_decl $main C_MAX] \
        {kind constant name C_MAX type integer init 7 line 20}
    check_eq "control: v_x record unchanged" [proc_decl $inner v_x] \
        {kind variable name v_x type integer init {} line 11}
    check_eq "control: f_inc's local tmp is not a process declaration" [proc_decl $main tmp] {}
    check_eq "control: main process line" [field $main line] 16
    check_eq "control: main process label" [field $main label] main
    check_eq "control: other process line" [field $other line] 40
    check_eq "control: inner process line" [field $inner line] 9
} finally {
    cleanup_tmp_files
}

puts ""
puts "Passed: $::pass_count"
puts "Failed: $::fail_count"
exit [expr {$::fail_count > 0}]
