#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#57): a subprogram declared inside another is reported under
# its parent, in the parent's body_declarations, not beside it.
#
# Background: _scan_functions and _scan_procedures matched on the unmasked
# declarative part and advanced only past each header, so the next match was
# a nested subprogram's own keyword. One pass returned outer and inner
# subprograms side by side, and body_declarations held only variables and
# constants. The scanners now mask nested subprograms before matching, as the
# object scanners do, and each subprogram recurses into its own declarative
# part: nested functions and procedures follow its variables and constants.
#
# Controls hold before and after: subprograms with no nesting keep the same
# record.
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
    set dir [file join $base "aurig_core_nested_subprogram_recursion_[pid]_[clock milliseconds]"]
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

# Sorted {kind:name@line ...} of a list of declaration records.
proc summary {L} {
    set out {}
    foreach d $L {
        lappend out "[dict get $d kind]:[dict get $d name]@[dict get $d line]"
    }
    return [lsort $out]
}

# body_declarations of a record, or {}.
proc body_of {d} {
    if {![dict exists $d body_declarations]} { return {} }
    return [dict get $d body_declarations]
}

# Field $key of record $d, or "<absent>"; never raises, so a record missing
# on an unpatched tree fails its assertion instead of aborting the script.
proc field {d key} {
    if {![dict exists $d $key]} { return "<absent>" }
    return [dict get $d $key]
}

# Whether record $d has body_declarations, or "<absent>" when $d itself is
# missing, so the check cannot pass on a record that was never found.
proc has_body {d} {
    if {![dict exists $d name]} { return "<absent>" }
    return [dict exists $d body_declarations]
}

# Declarations of the first architecture.
proc arch_decls {parsed} {
    return [dict get [lindex [dict get $parsed architectures] 0] declarations]
}

# Sorted summary of the functions and procedures among the architecture
# declarations.
proc arch_subprograms {parsed} {
    set L {}
    foreach d [arch_decls $parsed] {
        if {[dict get $d kind] in {function procedure}} { lappend L $d }
    }
    return [summary $L]
}

# Record reached from the architecture declarations by the path of names
# $args, each looked up in the previous one's body_declarations.
proc arch_path {parsed args} {
    set L [arch_decls $parsed]
    set d {}
    foreach name $args {
        set d [named $L $name]
        set L [body_of $d]
    }
    return $d
}

set ::tmp_dir [make_tmp_dir]
try {
    # Line numbers are part of the assertions: keep this layout in step.
    set arch_src [tmp_vhd_lines nested {
        {library ieee;}
        {use ieee.std_logic_1164.all;}
        {}
        {entity d is}
        {  port (clk : in std_logic);}
        {end entity;}
        {}
        {architecture rtl of d is}
        {  procedure p_pp(x : integer) is}
        {    variable v_a : integer;}
        {    procedure inner_p(y : integer) is}
        {      variable v_ip : integer;}
        {    begin}
        {    end procedure inner_p;}
        {  begin}
        {  end procedure p_pp;}
        {  procedure p_pf(x : integer) is}
        {    function inner_f(y : integer) return integer is}
        {    begin}
        {      return y;}
        {    end function inner_f;}
        {    constant C_B : integer := 1;}
        {  begin}
        {  end procedure p_pf;}
        {  procedure l1(x : integer) is}
        {    function l2(y : integer) return integer is}
        {      procedure l3(z : integer) is}
        {        variable v_l3 : integer;}
        {      begin}
        {      end procedure l3;}
        {    begin}
        {      return y;}
        {    end function l2;}
        {  begin}
        {  end procedure l1;}
        {  function f_proto(x : integer) return integer is}
        {    procedure np(y : integer);}
        {    function nf(y : integer) return integer;}
        {    variable v_fp : integer;}
        {  begin}
        {    return x;}
        {  end function f_proto;}
        {  procedure c_plain(x : integer) is}
        {    variable v_h : integer;}
        {    constant C_H : integer := 2;}
        {  begin}
        {  end procedure c_plain;}
        {  function c_fplain(x : integer) return integer is}
        {  begin}
        {    return x;}
        {  end function c_fplain;}
        {begin}
        {end architecture;}
    }]

    set A [parse $arch_src]

    # --- Positive: only outer-level subprograms at architecture level ----------
    check_eq "positive: nested subprograms are not listed at architecture level" \
        [arch_subprograms $A] \
        [lsort {procedure:p_pp@9 procedure:p_pf@17 procedure:l1@25 function:f_proto@36 procedure:c_plain@43 function:c_fplain@48}]

    # --- Positive: a procedure declaring a procedure ----------------------------
    check_eq "positive: procedure declaring a procedure lists it under its parent" \
        [summary [body_of [arch_path $A p_pp]]] \
        [lsort {variable:v_a@10 procedure:inner_p@11}]
    check_eq "positive: the nested procedure keeps its own locals" \
        [summary [body_of [arch_path $A p_pp inner_p]]] \
        {variable:v_ip@12}

    # --- Positive: a procedure declaring a function -----------------------------
    check_eq "positive: procedure declaring a function lists it under its parent" \
        [summary [body_of [arch_path $A p_pf]]] \
        [lsort {function:inner_f@18 constant:C_B@22}]
    set inner_f [arch_path $A p_pf inner_f]
    check_eq "positive: the nested function keeps its signature" \
        [list [field $inner_f return] [field $inner_f params] [field $inner_f purity]] \
        {integer {y : integer} pure}
    check_eq "positive: a nested function with no locals has no body_declarations" \
        [has_body $inner_f] 0

    # --- Positive: two levels deep (procedure > function > procedure) -----------
    check_eq "positive: two levels deep, level 1 holds level 2" \
        [summary [body_of [arch_path $A l1]]] \
        {function:l2@26}
    check_eq "positive: two levels deep, level 2 holds level 3" \
        [summary [body_of [arch_path $A l1 l2]]] \
        {procedure:l3@27}
    check_eq "positive: two levels deep, level 3 keeps its locals" \
        [summary [body_of [arch_path $A l1 l2 l3]]] \
        {variable:v_l3@28}

    # --- Positive: nested prototypes --------------------------------------------
    check_eq "positive: nested prototypes are listed under their parent" \
        [summary [body_of [arch_path $A f_proto]]] \
        [lsort {procedure:np@37 function:nf@38 variable:v_fp@39}]
    check_eq "positive: nested prototypes have no body_declarations" \
        [list [has_body [arch_path $A f_proto np]] [has_body [arch_path $A f_proto nf]]] \
        {0 0}

    # --- Positive: direct scanner calls -----------------------------------------
    set t "procedure outer(x : integer) is\n  function inner_f(y : integer) return integer is\n  begin\n    return y;\n  end function inner_f;\n  procedure inner_p(y : integer) is\n  begin\n  end procedure inner_p;\nbegin\nend procedure outer;\n"
    set names {}
    foreach d [::aurig::core::analyze::_scan_procedures $t 1] { lappend names [dict get $d name] }
    check_eq "positive: _scan_procedures returns only the outer-level procedure" $names {outer}
    check_eq "positive: _scan_functions returns no nested function" \
        [::aurig::core::analyze::_scan_functions $t 1] {}

    # --- Positive: a keyword inside a string literal is not a subprogram -------
    # The outer-level walk must skip strings: taken for a subprogram, the
    # literal's "interior" ran on to the next subprogram's end and blanked a
    # real sibling (PR #78 review).
    set t "constant msg : string := \"procedure begin\";\nprocedure sib(x : integer) is\nbegin\nend procedure sib;\n"
    set got {}
    foreach d [::aurig::core::analyze::_scan_procedures $t 1] { lappend got "[dict get $d name]@[dict get $d line]" }
    check_eq "positive: _scan_procedures finds a sibling after \"procedure ...\" in a string" $got {sib@2}
    set t "constant msg : string := \"function begin\";\nfunction sib(x : integer) return integer is\nbegin\n  return x;\nend function sib;\n"
    set got {}
    foreach d [::aurig::core::analyze::_scan_functions $t 1] { lappend got "[dict get $d name]@[dict get $d line]" }
    check_eq "positive: _scan_functions finds a sibling after \"function ...\" in a string" $got {sib@2}

    # --- Positive: a nested impure prototype does not lend its prefix ----------
    # Masking a procedure's interior left the nested prototype's `impure`
    # standing alone before the next sibling's `function`, so the sibling was
    # reported impure and its comment was looked up from the prototype's line
    # (PR #78 review). Through vhdlscan, so the comment association is real.
    set imp_src [tmp_vhd_lines impure_prefix {
        {entity d is}
        {end entity;}
        {architecture rtl of d is}
        {  -- outer comment}
        {  procedure outer(x : integer) is}
        {    -- np comment}
        {    impure function np(y : integer) return integer;}
        {  begin}
        {  end procedure outer;}
        {  -- sib comment}
        {  function sib(x : integer) return integer is}
        {  begin}
        {    return x;}
        {  end function sib;}
        {begin}
        {end architecture;}
    }]
    set sib [named [arch_decls [parse $imp_src]] sib]
    set sib_args [lindex [field $sib args] 0]
    check_eq "positive: sibling after a nested impure prototype is pure" \
        [list [field $sib line] [field $sib_args purity]] {11 pure}
    check_eq "positive: sibling after a nested impure prototype keeps its own comment" \
        [field $sib comment] {sib comment}

    # --- Control: an attribute specification before sibling subprograms --------
    # Holds before and after. The `: procedure is "..."` entity class is not a
    # subprogram header; a mask that took it for one would blank the siblings.
    set t "procedure pp is\nbegin\nend procedure pp;\nattribute foo of pp : procedure is \"bar\";\nprocedure sib(x : integer) is\nbegin\nend procedure sib;\nfunction sf(x : integer) return integer is\nbegin\n  return x;\nend function sf;\n"
    set got {}
    foreach d [::aurig::core::analyze::_scan_procedures $t 1] { lappend got "procedure:[dict get $d name]@[dict get $d line]" }
    foreach d [::aurig::core::analyze::_scan_functions $t 1] { lappend got "function:[dict get $d name]@[dict get $d line]" }
    check_eq "control: attribute specification before sibling subprograms" \
        $got {procedure:pp@1 procedure:sib@5 function:sf@8}

    # --- Controls: no nesting, record unchanged ---------------------------------
    check_eq "control: procedure with no nesting keeps the same body_declarations" \
        [body_of [arch_path $A c_plain]] \
        [list \
            [dict create kind variable name v_h type integer init {} line 44] \
            [dict create kind constant name C_H type integer init 2 line 45]]
    check_eq "control: function with no locals has no body_declarations" \
        [has_body [arch_path $A c_fplain]] 0
    set t "procedure a(x : integer) is\n  variable v : integer;\nbegin\nend procedure a;\nfunction b(y : integer) return integer is\nbegin\n  return y;\nend function b;\n"
    check_eq "control: _scan_procedures with no nesting" \
        [::aurig::core::analyze::_scan_procedures $t 1] \
        [list [dict create kind procedure name a params {x : integer} line 1 \
            body_declarations [list [dict create kind variable name v type integer init {} line 2]]]]
    check_eq "control: _scan_functions with no nesting" \
        [::aurig::core::analyze::_scan_functions $t 1] \
        [list [dict create name b return integer params {y : integer} purity pure line 5]]
} finally {
    cleanup_tmp_files
}

puts ""
puts "Passed: $::pass_count"
puts "Failed: $::fail_count"
exit [expr {$::fail_count > 0}]
