#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#76): _find_decl_body_begin must find the `begin` of a
# declarative part that contains a subprogram header with no body.
#
# Background: the proc added a depth level for every `function` / `procedure`
# keyword. A prototype, an `is new` instantiation and an attribute
# specification entity class (`: procedure is "..."`) have no `end` to close
# that level, so the depth never returned to 0, the `begin` was never found
# and the proc returned -1. Nothing reported it:
#   - a subprogram containing one returned no body_declarations
#   - a process containing one returned no declarations and an empty body
#   - _find_subprogram_end returned -1 for the enclosing subprogram
# The keyword is now classified by _classify_subprogram_header (#73) and
# only a body adds a level.
#
# Controls hold before and after: a nested body closed by `end procedure X;`
# or by `end;`, and declarative parts with no subprogram at all.
#
# Since #57 a subprogram nested in another is listed in its parent's
# body_declarations, after the parent's variables and constants, so the
# body_declarations assertions below also name the nested subprogram (prototype,
# instantiation or body) at its own source line. What this test is about is
# unchanged: the locals before and after it are still found.
#=============================================================================

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
    set dir [file join $base "aurig_core_decl_body_begin_[pid]_[clock milliseconds]"]
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

# Record named $name in list $L, or {}.
proc named {L name} {
    foreach d $L {
        if {[dict get $d name] eq $name} { return $d }
    }
    return {}
}

# Process labelled $label in the first architecture, or {}.
proc process_named {parsed label} {
    set arch [lindex [dict get $parsed architectures] 0]
    foreach p [dict get $arch processes] {
        if {[dict get $p label] eq $label} { return $p }
    }
    return {}
}

# {kind:name@line ...} of a list of declaration records.
proc summary {L} {
    set out {}
    foreach d $L {
        lappend out "[dict get $d kind]:[dict get $d name]@[dict get $d line]"
    }
    return $out
}

# Summary of the body_declarations of subprogram $name in architecture decls.
proc arch_body_decls {parsed name} {
    set d [named [dict get [lindex [dict get $parsed architectures] 0] declarations] $name]
    if {![dict exists $d body_declarations]} { return {} }
    return [summary [dict get $d body_declarations]]
}

# Summary of the declarations of process $label.
proc process_decls {parsed label} {
    set p [process_named $parsed $label]
    if {![dict exists $p declarations]} { return {} }
    return [summary [dict get $p declarations]]
}

proc process_body {parsed label} {
    set p [process_named $parsed $label]
    if {![dict exists $p body]} { return "<absent>" }
    return [dict get $p body]
}

set ::tmp_dir [make_tmp_dir]
try {
    # Line numbers are part of the assertions: keep this layout in step.
    set arch_src [tmp_vhd_lines subprograms {
        {library ieee;}
        {use ieee.std_logic_1164.all;}
        {}
        {entity d is}
        {  port (clk : in std_logic);}
        {end entity;}
        {}
        {architecture rtl of d is}
        {  attribute dont_touch : string;}
        {  procedure p_proto(x : integer) is}
        {    procedure helper(y : integer);}
        {    variable v_a : integer;}
        {    constant C_A : integer := 1;}
        {  begin}
        {    v_a := x;}
        {  end procedure p_proto;}
        {  function f_pure_proto(x : integer) return integer is}
        {    pure function g(y : integer) return integer;}
        {    variable v_b : integer;}
        {  begin}
        {    return x;}
        {  end function f_pure_proto;}
        {  procedure p_bare_proto(x : integer) is}
        {    procedure tick;}
        {    variable v_c : integer;}
        {  begin}
        {  end procedure p_bare_proto;}
        {  procedure p_inst(x : integer) is}
        {    procedure p_i is new gen_p generic map (W => 8);}
        {    variable v_d : integer;}
        {  begin}
        {  end procedure p_inst;}
        {  procedure p_attr(x : integer) is}
        {    procedure h is begin end procedure h;}
        {    attribute dont_touch of h : procedure is "true";}
        {    variable v_e : integer;}
        {  begin}
        {  end procedure p_attr;}
        {  procedure c_body(x : integer) is}
        {    procedure h2(y : integer) is}
        {    begin}
        {    end procedure h2;}
        {    variable v_f : integer;}
        {  begin}
        {  end procedure c_body;}
        {  procedure c_end_semi(x : integer) is}
        {    procedure h3 is begin end;}
        {    variable v_g : integer;}
        {  begin}
        {  end procedure c_end_semi;}
        {  procedure c_plain(x : integer) is}
        {    variable v_h : integer;}
        {  begin}
        {  end procedure c_plain;}
        {begin}
        {end architecture;}
    }]

    set proc_src [tmp_vhd_lines processes {
        {library ieee;}
        {use ieee.std_logic_1164.all;}
        {}
        {entity e is}
        {  port (clk : in std_logic);}
        {end entity;}
        {}
        {architecture rtl of e is}
        {  attribute dont_touch : string;}
        {begin}
        {  p_proto : process (clk)}
        {    procedure tick(x : integer);}
        {    variable v_p : integer;}
        {  begin}
        {    v_p := 1;}
        {  end process;}
        {  p_pure_proto : process (clk)}
        {    pure function g(y : integer) return integer;}
        {    constant C_P : integer := 2;}
        {  begin}
        {    null;}
        {  end process;}
        {  p_inst : process (clk)}
        {    procedure p_i is new gen_p generic map (W => 8);}
        {    variable v_i : integer;}
        {  begin}
        {    null;}
        {  end process;}
        {  p_attr : process (clk)}
        {    procedure tock is begin end procedure tock;}
        {    attribute dont_touch of tock : procedure is "true";}
        {    variable v_t : integer;}
        {  begin}
        {    null;}
        {  end process;}
        {  c_body : process (clk)}
        {    procedure tock2 is begin end procedure tock2;}
        {    variable v_cb : integer;}
        {  begin}
        {    v_cb := 0;}
        {  end process;}
        {  c_plain : process (clk)}
        {    variable v_cp : integer;}
        {  begin}
        {    v_cp := 0;}
        {  end process;}
        {end architecture;}
    }]

    set pkgbody_src [tmp_vhd_lines package_body {
        {package pk is}
        {  procedure pb_proto(x : integer);}
        {  procedure pb_plain(x : integer);}
        {end package pk;}
        {}
        {package body pk is}
        {  procedure pb_proto(x : integer) is}
        {    procedure helper(y : integer);}
        {    variable v_pb : integer;}
        {  begin}
        {  end procedure pb_proto;}
        {  procedure pb_plain(x : integer) is}
        {    variable v_pp : integer;}
        {  begin}
        {  end procedure pb_plain;}
        {end package body pk;}
    }]

    set A [parse $arch_src]
    set P [parse $proc_src]
    set B [parse $pkgbody_src]

    # --- Positive: a subprogram containing a header with no body keeps its locals
    # #57: the nested prototype helper (line 11) moved from the architecture's
    # flat list into p_proto's body_declarations, after its locals.
    check_eq "positive: procedure containing a procedure prototype keeps its locals" \
        [arch_body_decls $A p_proto] {variable:v_a@12 constant:C_A@13 procedure:helper@11}
    # #57: the nested prototype g (line 18) moved from the flat list into
    # f_pure_proto's body_declarations.
    check_eq "positive: function containing a pure function prototype keeps its locals" \
        [arch_body_decls $A f_pure_proto] {variable:v_b@19 function:g@18}
    # Unchanged by #57: `procedure tick;` is a parameterless prototype, which
    # _scan_procedures does not record at any level.
    check_eq "positive: procedure containing a parameterless prototype keeps its locals" \
        [arch_body_decls $A p_bare_proto] {variable:v_c@25}
    # #57: the nested instantiation p_i (line 29) moved from the flat list into
    # p_inst's body_declarations; _scan_procedures records `procedure ... is
    # new` as a procedure, as it does at architecture level.
    check_eq "positive: procedure containing \`procedure ... is new\` keeps its locals" \
        [arch_body_decls $A p_inst] {variable:v_d@30 procedure:p_i@29}
    # #57: the nested body h (line 34) moved from the flat list into p_attr's
    # body_declarations. The attribute specification itself is not recorded.
    check_eq "positive: procedure containing an attribute specification keeps its locals" \
        [arch_body_decls $A p_attr] {variable:v_e@36 procedure:h@34}

    # #57: the nested prototype helper (line 8) moved from the package body's
    # procedures into pb_proto's body_declarations.
    set pb [named [dict get [lindex [dict get $B package_bodies] 0] procedures] pb_proto]
    check_eq "positive: package-body procedure containing a prototype keeps its locals" \
        [summary [expr {[dict exists $pb body_declarations] ? [dict get $pb body_declarations] : {}}]] \
        {variable:v_pb@9 procedure:helper@8}

    # --- Positive: a process containing a header with no body keeps its declarations
    check_eq "positive: process containing a procedure prototype keeps its declarations" \
        [process_decls $P p_proto] {variable:v_p@13 procedure:tick@12}
    check_eq "positive: process containing a procedure prototype keeps its body" \
        [process_body $P p_proto] {v_p := 1;}
    check_eq "positive: process containing a pure function prototype keeps its declarations" \
        [process_decls $P p_pure_proto] {constant:C_P@19 function:g@18}
    check_eq "positive: process containing \`procedure ... is new\` keeps its declarations" \
        [process_decls $P p_inst] {variable:v_i@25 procedure:p_i@24}
    check_eq "positive: process containing \`procedure ... is new\` keeps its body" \
        [process_body $P p_inst] {null;}
    check_eq "positive: process containing an attribute specification keeps its declarations" \
        [process_decls $P p_attr] {variable:v_t@32 procedure:tock@30}
    check_eq "positive: process containing an attribute specification keeps its body" \
        [process_body $P p_attr] {null;}

    # --- Positive: direct calls -------------------------------------------------
    set t "procedure inner(y : integer);\n  variable vo : integer;\nbegin\nend;"
    check_eq "positive: _find_decl_body_begin past a prototype" \
        [::aurig::core::analyze::_find_decl_body_begin $t 0 -1] [string first "begin" $t]
    set t "procedure outer(x : integer) is\n  procedure inner(y : integer);\nbegin\nend procedure outer;\nsignal s : bit;"
    check_eq "positive: _find_subprogram_end of a subprogram containing a prototype" \
        [::aurig::core::analyze::_find_subprogram_end $t 0] [expr {[string first "outer;" $t] + 5}]

    # --- Controls: hold before and after ----------------------------------------
    # #57: the nested body h2 (line 40) moved from the flat list into c_body's
    # body_declarations.
    check_eq "control: procedure containing a body closed by \`end procedure X;\`" \
        [arch_body_decls $A c_body] {variable:v_f@43 procedure:h2@40}
    # #57: the nested body h3 (line 47) moved from the flat list into
    # c_end_semi's body_declarations.
    check_eq "control: procedure containing a body closed by \`end;\`" \
        [arch_body_decls $A c_end_semi] {variable:v_g@48 procedure:h3@47}
    check_eq "control: procedure with no nested subprogram" \
        [arch_body_decls $A c_plain] {variable:v_h@52}
    check_eq "control: process containing a body" \
        [process_decls $P c_body] {variable:v_cb@38 procedure:tock2@37}
    check_eq "control: process containing a body keeps its body" \
        [process_body $P c_body] {v_cb := 0;}
    check_eq "control: process with no subprogram" \
        [process_decls $P c_plain] {variable:v_cp@43}
    set pp [named [dict get [lindex [dict get $B package_bodies] 0] procedures] pb_plain]
    check_eq "control: package-body procedure with no nested subprogram" \
        [summary [dict get $pp body_declarations]] {variable:v_pp@13}
    set t "variable vo : integer;\nbegin\nend;"
    check_eq "control: _find_decl_body_begin with no subprogram" \
        [::aurig::core::analyze::_find_decl_body_begin $t 0 -1] [string first "begin" $t]
} finally {
    cleanup_tmp_files
}

puts ""
puts "Passed: $::pass_count"
puts "Failed: $::fail_count"
exit [expr {$::fail_count > 0}]
