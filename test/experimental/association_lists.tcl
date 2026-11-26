# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

set r [::vhdl_index::analyze_file [file join $tests fixtures association-maps.vhd.fixture] 2008]
set v [::vhdl_index::regions::view $r]
set b [scope_find $v block b:]
lassign [dict get [scope_shape $v $b] maps] g p
lassign [dict get $g associations] positional named
check positional positional [dict get $positional form]
check nested_actual {f((0 => 1, others => 2), "=>,", ',')} [surface $r [dict get $positional actual_span]]
check comma , [surface $r [lindex [dict get $g separator_spans] 0]]
check open ( [surface $r [dict get $g open_span]]
check close ) [surface $r [dict get $g close_span]]
check named named [dict get $named form]
check formal t [surface $r [dict get $named formal_span]]
check arrow => [surface $r [dict get $named arrow_span]]
check actual integer [surface $r [dict get $named actual_span]]
check port_shape parsed [dict get $p association_validation]
set actual [lindex [dict get $p associations] 0]
check inertial inertial [dict get $actual actual_kind]
check external {inertial f(\input,=>\, <<signal .e.s : bit>>)} [surface $r [dict get $actual actual_span]]
scope_integrity $r $v

foreach {payload code count} {
    {} ASSOCIATION_MISSING_ELEMENT 0
    {, a => 2} ASSOCIATION_MISSING_ELEMENT 1
    {=> 1, x => 2} ASSOCIATION_MISSING_FORMAL 1
    {a => , b => 2} ASSOCIATION_MISSING_ACTUAL 1
    {a => b => 1, c => 2} ASSOCIATION_DUPLICATE_ARROW 1
    {a => 1,} ASSOCIATION_TRAILING_COMMA 1
    {a => 1, 2, b => 3} ASSOCIATION_POSITIONAL_AFTER_NAMED 2
    {1 2, b => 3} ASSOCIATION_MISSING_SEPARATOR 1
    {a = > 1, b => 3} ASSOCIATION_MALFORMED_ARROW 1
    {(a + b) => 1, b => 3} ASSOCIATION_EXPECTED_NAME 1
    {inertial f(a), b => 3} ASSOCIATION_INERTIAL_CONTEXT 1
    {open, b => open} {} 2
    {conv(p(7 downto 0)) => work.f(1), b.q(3) => 'x'} {} 2
    {a => s'event, b => bit'(d)} {} 2
} {
    foreach edition {1993 2002 2008} {
        set r [scope_input "entity e is end; architecture a of e is begin b: block generic (a : integer); generic map ($payload); begin end block; end;" $edition]
        set v [::vhdl_index::regions::view $r]
        set map [lindex [dict get [scope_shape $v [scope_find $v block b:]] maps] 0]
        set codes {}
        foreach diagnostic [dict get $map association_diagnostics] {lappend codes [dict get $diagnostic code]}
        check "$edition $payload diagnostics" $code $codes
        check "$edition $payload survivors" $count [llength [dict get $map associations]]
    }
}
puts "Bounded association list assertions passed"
