# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

set baseline_probe [scope_input {entity e is begin assert true; end;}]
set view [::vhdl_index::regions::view $baseline_probe]
set entity [scope_find $view entity {entity e}]
check recognizes_assertion 1 [llength [scope_rows $view $entity concurrent_assertions]]

foreach edition {1993 2002 2008} {
    set r [scope_input {entity e is begin
        \a label\: postponed assert f("report", 'R', \severity\) report "severity" severity warning;
        assert true;
    end;
    architecture a of e is begin assert x severity note; end;} $edition]
    set v [::vhdl_index::regions::view $r]
    set e [scope_find $v entity {entity e}]
    set a [scope_find $v architecture {architecture a}]
    check complete complete [scope_complete $v $e concurrent_assertions]
    lassign [scope_rows $v $e concurrent_assertions] first second
    foreach {key spelling} {
        label_span "\\a label\\" colon_span : postponed_span postponed assert_span assert
        condition_span {f("report", 'R', \severity\)} report_keyword_span report report_span {"severity"}
        severity_keyword_span severity severity_span warning terminator_span {;}
    } {
        check $key $spelling [surface $r [dict get $first $key]]
    }
    check owner $e [dict get $first owner_occurrence_id]
    check second_condition true [surface $r [dict get $second condition_span]]
    check severity_only note [surface $r [dict get [lindex [scope_rows $v $a concurrent_assertions] 0] severity_span]]
    scope_integrity $r $v
}
foreach {bad code} {
    {assert ;} ASSERTION_MISSING_CONDITION
    {assert true report ;} ASSERTION_MISSING_REPORT
    {assert true severity ;} ASSERTION_MISSING_SEVERITY
    {assert true severity note report "backwards";} ASSERTION_CLAUSE_ORDER
    {assert true} ASSERTION_EXPECTED_SEMICOLON
} {
    set r [scope_input "entity e is end; architecture a of e is begin $bad keep: component c; assert true; end;" 2008]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set d [::vhdl_index::query::direct $v $a concurrent_assertions]
    check partial partial [dict get $d completeness]
    set proof [lindex [dict get $d evidence] 0]
    check diagnostic $code [dict get [lindex [dict get $proof diagnostics] 0] code]
    check sibling 1 [llength [scope_rows $v $a concurrent_assertions]]
    check instance 1 [llength [scope_rows $v $a instantiations]]
    scope_integrity $r $v
}
puts {Concurrent assertion assertions passed}
