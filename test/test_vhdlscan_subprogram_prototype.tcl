# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression: subprogram prototypes (procedure/function declarations without
# a body) must not leak their `signal`/`variable` parameters into the
# enclosing architecture or package declaration scope.
#
# Background: in PR #33 the architecture-section scanners were rewritten to
# use _mask_subprograms + _find_vhdl_statement_semicolon. The initial fix only
# masked subprograms WITH a body (function|procedure ... begin ... end ;).
# Prototypes ending at the first top-level `;` were unmasked, so their
# `signal foo : ...` parameters were emitted as architecture signals.
# _mask_subprograms now runs a second pass that masks each remaining
# function/procedure keyword up to the next top-level `;`.
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

proc tmp_vhd {basename content} {
    set path [file join [file dirname [info script]] "_tmp_${basename}.vhd"]
    set fp [open $path w]
    puts $fp $content
    close $fp
    lappend ::tmp_files $path
    return $path
}

proc cleanup_tmp_files {} {
    foreach path $::tmp_files {
        catch {file delete -- $path}
    }
}

# ----------------------------------------------------------------------------
# Case 1: architecture with a procedure prototype + a real signal
# ----------------------------------------------------------------------------
set path [tmp_vhd "arch_proto" {
library ieee;
use ieee.std_logic_1164.all;

entity arch_with_proto is
    port (clk : in std_logic);
end entity arch_with_proto;

architecture rtl of arch_with_proto is
    procedure poke(signal s : out std_logic; v : in std_logic);
    signal real_signal : std_logic;
begin
    real_signal <= '0';
end architecture rtl;
}]

set parsed [::aurig::core::analyze::vhdlscan -in $path -verbosity 0]
set decls [dict get [lindex [dict get $parsed architectures] 0] declarations]

set signal_names {}
set procedure_names {}
foreach d $decls {
    set kind [dict get $d kind]
    if {$kind eq "signal"}    { lappend signal_names    [dict get $d name] }
    if {$kind eq "procedure"} { lappend procedure_names [dict get $d name] }
}

check "architecture procedure prototype emits the procedure declaration" \
    {[lsearch -exact $procedure_names "poke"] >= 0}
check "architecture procedure prototype does NOT leak its 'signal s' parameter" \
    {[lsearch -exact $signal_names "s"] < 0}
check "real architecture signal is still emitted" \
    {[lsearch -exact $signal_names "real_signal"] >= 0}
check "exactly one signal declaration in the architecture" \
    {[llength $signal_names] == 1}

# ----------------------------------------------------------------------------
# Case 2: package decl with overloaded procedure prototypes carrying `signal`
# parameters and additional package-level subprogram declarations
# ----------------------------------------------------------------------------
set path [tmp_vhd "pkg_proto_overloads" {
library ieee;
use ieee.std_logic_1164.all;

package pkg_overloads is
    procedure reset(signal s : out std_logic);
    procedure reset(signal v : out std_logic_vector);
    function compute(signal sig_in : in std_logic) return std_logic;
end package pkg_overloads;
}]

set parsed [::aurig::core::analyze::vhdlscan -in $path -verbosity 0]
set decls [dict get [lindex [dict get $parsed packages] 0] declarations]

set pkg_signal_names {}
set pkg_procedure_names {}
set pkg_function_names {}
foreach d $decls {
    set kind [dict get $d kind]
    if {$kind eq "signal"}    { lappend pkg_signal_names    [dict get $d name] }
    if {$kind eq "procedure"} { lappend pkg_procedure_names [dict get $d name] }
    if {$kind eq "function"}  { lappend pkg_function_names  [dict get $d name] }
}

check "package overloaded procedures both emitted" \
    {[llength $pkg_procedure_names] == 2 && [lindex $pkg_procedure_names 0] eq "reset"}
check "package function prototype with signal param emitted" \
    {[lsearch -exact $pkg_function_names "compute"] >= 0}
check "package procedure prototypes do NOT leak 'signal s' as a package signal" \
    {[lsearch -exact $pkg_signal_names "s"] < 0}
check "package procedure prototypes do NOT leak 'signal v' as a package signal" \
    {[lsearch -exact $pkg_signal_names "v"] < 0}
check "package function prototype does NOT leak 'signal sig_in' as a package signal" \
    {[lsearch -exact $pkg_signal_names "sig_in"] < 0}
check "no spurious package-level signals from overloaded prototypes" \
    {[llength $pkg_signal_names] == 0}

# ----------------------------------------------------------------------------
# Case 3: architecture mixing a real signal, a function with a body that
# declares a variable internally, and a procedure prototype with a signal
# parameter. Variable inside function body must not leak to architecture
# variables, and the prototype's signal parameter must not leak to
# architecture signals.
# ----------------------------------------------------------------------------
set path [tmp_vhd "arch_mixed_subprograms" {
library ieee;
use ieee.std_logic_1164.all;

entity arch_mixed is
    port (clk : in std_logic);
end entity arch_mixed;

architecture rtl of arch_mixed is
    function inc1(x : integer) return integer is
        variable internal : integer;
    begin
        internal := x + 1;
        return internal;
    end function inc1;

    procedure tap(signal sig_param : in std_logic; v : in integer);

    signal real_sig : std_logic;
    variable real_var : integer;
begin
    real_sig <= '0';
end architecture rtl;
}]

set parsed [::aurig::core::analyze::vhdlscan -in $path -verbosity 0]
set decls [dict get [lindex [dict get $parsed architectures] 0] declarations]

set sig_names {}
set var_names {}
set fn_names {}
set proc_names {}
foreach d $decls {
    switch -- [dict get $d kind] {
        signal    { lappend sig_names  [dict get $d name] }
        variable  { lappend var_names  [dict get $d name] }
        function  { lappend fn_names   [dict get $d name] }
        procedure { lappend proc_names [dict get $d name] }
    }
}

check "mixed: function with body emitted" \
    {[lsearch -exact $fn_names "inc1"] >= 0}
check "mixed: procedure prototype emitted" \
    {[lsearch -exact $proc_names "tap"] >= 0}
check "mixed: 'variable internal' inside function body does NOT leak as architecture variable" \
    {[lsearch -exact $var_names "internal"] < 0}
check "mixed: procedure prototype 'signal sig_param' does NOT leak as architecture signal" \
    {[lsearch -exact $sig_names "sig_param"] < 0}
check "mixed: real_sig is the only signal" \
    {$sig_names eq {real_sig}}
check "mixed: real_var is the only variable" \
    {$var_names eq {real_var}}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
cleanup_tmp_files
puts ""
puts "============================================================"
puts "test_vhdlscan_subprogram_prototype.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
