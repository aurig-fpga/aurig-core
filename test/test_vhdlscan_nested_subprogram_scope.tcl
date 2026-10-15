# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression (#58): the architecture declarative part must end at the
# architecture's own `begin`, not at the `begin` of a subprogram.
#
# Background: split_arch_decl_body tracked "a subprogram header has been seen
# and its `begin` has not" with one bit. A nested subprogram set it a second
# time without counting, so its `begin` cleared it and the enclosing
# subprogram's `begin` was taken as the architecture's: everything after it,
# including the whole architecture body, was lost without an error. The same
# arming logic also fired on headers that never have a `begin`: an attribute
# specification (`: procedure is "..."`), a package declaration, and
# package/subprogram instantiations (`is new`), all raising MISSING_BEGIN.
#
# The prototype cases are CONTROLS: they parse before and after. They are
# here to catch a counter added without prototype classification, which
# turns the old stale arm into a real count and consumes the architecture's
# own `begin`.
#
# The declaration scanner lists nested subprograms (and the constants of a
# nested package) as architecture-level declarations. That is #57, not
# changed here; where a case below lists them, it records current behaviour
# knowingly and does not endorse it.
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
    set dir [file join $base "aurig_core_nested_subprogram_scope_[pid]_[clock milliseconds]"]
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

# Fixture: entity e, architecture rtl with signal s, the declarative lines
# $decl, signal s_last, `begin`, then process p_main (body `s_last <= s;`).
proc arch_fixture {basename decl} {
    set lines {
        {entity e is}
        {end entity;}
        {architecture rtl of e is}
        {  signal s : integer;}
    }
    lappend lines {*}$decl \
        {  signal s_last : integer;} \
        {begin} \
        {  p_main : process(s)} \
        {  begin} \
        {    s_last <= s;} \
        {  end process p_main;} \
        {end architecture rtl;}
    return [tmp_vhd_lines $basename $lines]
}

# Summary of the single architecture of $path:
#   decls: sorted "kind:name", with "(N)" when it has N body_declarations
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
# on an unpatched tree documents the truncation or the error.
proc check_summary {label path decls} {
    set got [summary $path]
    set want [list decls [lsort $decls] procs {{p_main=s_last <= s;}}]
    if {$got eq $want} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (expected $want, got $got)"
        incr ::fail_count
    }
}

set ::base {signal:s signal:s_last}

set ::tmp_dir [make_tmp_dir]
try {

# ----------------------------------------------------------------------------
# Positive: nested subprograms. Each previously truncated the declarative
# part at the inner subprogram and lost the architecture body, silently.
# inner_f, l2, l3 and pi appearing at architecture level is #57.
# ----------------------------------------------------------------------------
check_summary "positive: function nested in a procedure, with declarations after it" \
    [arch_fixture nested {
        {  procedure outer(x : in integer) is}
        {    variable v : integer;}
        {    function inner_f(a : integer) return integer is}
        {    begin}
        {      return a + 1;}
        {    end function inner_f;}
        {  begin}
        {    v := inner_f(x);}
        {  end procedure outer;}
        {  function late_f(b : integer) return integer is}
        {  begin}
        {    return b;}
        {  end function late_f;}
    }] \
    [list {*}$::base {procedure:outer(1)} function:inner_f function:late_f]

check_summary "positive: three levels of nesting" \
    [arch_fixture two_levels {
        {  procedure l1 is}
        {    procedure l2 is}
        {      function l3 return integer is}
        {      begin}
        {        return 1;}
        {      end function l3;}
        {    begin}
        {    end procedure l2;}
        {  begin}
        {  end procedure l1;}
    }] \
    [list {*}$::base procedure:l1 procedure:l2 function:l3]

check_summary "positive: procedure nested in a function" \
    [arch_fixture nested_in_function {
        {  function fo(x : integer) return integer is}
        {    procedure pi is}
        {    begin}
        {    end procedure pi;}
        {  begin}
        {    return x;}
        {  end function fo;}
    }] \
    [list {*}$::base function:fo procedure:pi]

# ----------------------------------------------------------------------------
# Controls: prototypes. These parse before and after the fix; a counter
# without prototype classification breaks the last two.
# ----------------------------------------------------------------------------
check_summary "control: prototype between two subprogram bodies" \
    [arch_fixture proto_between {
        {  procedure a is}
        {  begin}
        {  end procedure a;}
        {  procedure p(x : integer; y : integer);}
        {  procedure b is}
        {  begin}
        {  end procedure b;}
    }] \
    [list {*}$::base procedure:a procedure:p procedure:b]

check_summary "control: prototype, then `type ... is`, then its body" \
    [arch_fixture proto_type_body {
        {  procedure p(x : integer);}
        {  type t is (A, B);}
        {  procedure p(x : integer) is}
        {  begin}
        {  end procedure p;}
    }] \
    [list {*}$::base procedure:p procedure:p type:t]

check_summary "control: body, prototype, `type ... is`, body" \
    [arch_fixture body_proto_type_body {
        {  procedure b is}
        {  begin}
        {  end procedure b;}
        {  procedure p(x : integer);}
        {  type t is (A, B);}
        {  procedure p(x : integer) is}
        {  begin}
        {  end procedure p;}
    }] \
    [list {*}$::base procedure:b procedure:p procedure:p type:t]

# ----------------------------------------------------------------------------
# Positive: headers that never have a `begin`. Each raised MISSING_BEGIN.
# ----------------------------------------------------------------------------
check_summary "positive: attribute specification on a procedure (`: procedure is`)" \
    [arch_fixture attr_spec_procedure {
        {  procedure pp is}
        {  begin}
        {  end procedure pp;}
        {  attribute foo : string;}
        {  attribute foo of pp : procedure is "bar";}
    }] \
    [list {*}$::base procedure:pp]

check_summary "positive: attribute specification on a function (`: function is`)" \
    [arch_fixture attr_spec_function {
        {  attribute foo : string;}
        {  function ff return integer is}
        {  begin}
        {    return 1;}
        {  end function ff;}
        {  attribute foo of ff : function is "bar";}
    }] \
    [list {*}$::base function:ff]

check_summary "positive: package instantiation (`package ... is new`)" \
    [arch_fixture package_instantiation {
        {  package fx is new work.gpkg generic map (W => 8);}
    }] \
    $::base

check_summary "positive: procedure instantiation (`procedure ... is new`)" \
    [arch_fixture procedure_instantiation {
        {  procedure pinst is new work.gproc generic map (T => integer);}
    }] \
    [list {*}$::base procedure:pinst]

# No function:finst: the function declaration scanner does not record a
# `function ... is new` instantiation (the procedure scanner does record
# pinst above). That is the scanner, not the split this test is about;
# recorded here as current behaviour, not endorsed.
check_summary "positive: function instantiation (`function ... is new`)" \
    [arch_fixture function_instantiation {
        {  function finst is new work.gfunc generic map (T => integer);}
    }] \
    $::base

# constant:k listed at architecture level is #57's misplacement, applied to
# a nested package; recorded here as current behaviour, not endorsed.
check_summary "positive: package declaration in the declarative part" \
    [arch_fixture package_declaration {
        {  package inner_pkg is}
        {    constant k : integer := 1;}
        {  end package inner_pkg;}
    }] \
    [list {*}$::base constant:k]

# ----------------------------------------------------------------------------
# Positive: a qualified expression in a parameter default. In character'(...)
# the first tick is a qualifier, not the start of a character literal. Read
# as the literal '(', the parenthesis is lost: with 'a' the parameter list's
# own `;` looks top-level and the header classifies as a prototype; with '"'
# a string opens and never closes. Either way the body was not counted and
# its `begin` was taken for the architecture's, silently.
# ----------------------------------------------------------------------------
check_summary "positive: qualified character'('a') in a parameter default" \
    [arch_fixture qualified_char_default {
        {  procedure p(c : character := character'('a'); n : integer := 1) is}
        {  begin}
        {  end procedure p;}
    }] \
    [list {*}$::base procedure:p]

check_summary "positive: qualified character'('\"') in a parameter default" \
    [arch_fixture qualified_quote_default {
        {  procedure p(c : character := character'('"'); n : integer := 1) is}
        {  begin}
        {  end procedure p;}
    }] \
    [list {*}$::base procedure:p]

# ----------------------------------------------------------------------------
# A comment between `is` and `new` is whitespace: the header is still an
# instantiation, not a body. vhdlscan strips comments before the splitter
# runs, so through vhdlscan the comment reaches the classifier only when the
# comment stripper misses it; it has no character-literal handling, so a '"'
# earlier on the same line hides the `--` from it. The direct call below is
# the classifier's own contract, independent of stripping.
# ----------------------------------------------------------------------------
check_summary "control: comment between `is` and `new`, stripped before the splitter" \
    [arch_fixture is_new_comment_stripped {
        {  procedure pinst is -- instantiate}
        {    new work.gproc generic map (T => integer);}
    }] \
    [list {*}$::base procedure:pinst]

check_summary "positive: comment between `is` and `new` that reaches the splitter" \
    [arch_fixture is_new_comment_kept {
        {  constant q : character := '"'; procedure pinst is -- instantiate}
        {    new work.gproc generic map (T => integer);}
    }] \
    [list {*}$::base constant:q procedure:pinst]

set chunk "architecture rtl of e is\n  procedure pinst is -- instantiate\n    new work.gproc generic map (T => integer);\n  signal s_last : integer;\nbegin\n  s_last <= s;\nend architecture rtl;\n"
if {[catch {::aurig::core::analyze::split_arch_decl_body $chunk} split options]} {
    set got [list ERROR [lindex [dict get $options -errorcode] 3]]
} else {
    set got [list [string range [dict get $split decl] end-23 end] [dict get $split body]]
}
set want [list {signal s_last : integer;} "begin\n  s_last <= s;\nend architecture rtl;"]
if {$got eq $want} {
    puts "PASS: positive: split_arch_decl_body, comment between `is` and `new`"
    incr ::pass_count
} else {
    puts "FAIL: positive: split_arch_decl_body, comment between `is` and `new` (expected $want, got $got)"
    incr ::fail_count
}

# ----------------------------------------------------------------------------
# Control: a subprogram without nesting
# ----------------------------------------------------------------------------
check_summary "control: one subprogram, no nesting" \
    [arch_fixture simple {
        {  procedure outer(x : in integer) is}
        {    variable v : integer;}
        {  begin}
        {    v := x;}
        {  end procedure outer;}
    }] \
    [list {*}$::base {procedure:outer(1)}]

} finally {
    cleanup_tmp_files
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "test_vhdlscan_nested_subprogram_scope.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
