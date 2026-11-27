# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

proc sequential_input {body {edition 2008} {limits {}}} {
    scope_input "entity e is end; architecture a of e is begin p: process begin\n$body\nend process p; end;" $edition $limits
}

proc sequential_expect {r row fields} {
    foreach {key expected} $fields {
        check $key $expected [surface $r [dict get $row $key]]
    }
}

proc lmap_spans {r spans} {
    set images {}
    foreach span $spans {lappend images [surface $r $span]}
    return $images
}

proc lmap_labels {rows} {
    set labels {}
    foreach row $rows {lappend labels [dict get $row label]}
    return $labels
}

foreach edition {1993 2002 2008} {
    set r [sequential_input {lab: assert a <= b report "message" severity warning;
        msg: report "status" severity note;
        idle: null;
        wait;
        sync: wait on a, b(1 to 2), r.member until a <= b for 1 ns;
        if a then
            case k is when 0 => loop assert hidden; end loop; when others => wait; end case;
        elsif b then null; else report "hidden"; end if;
        keep: assert true;} $edition]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    set a [scope_find $v architecture {architecture a}]
    check old_capability {} [scope_rows $v $a concurrent_assertions]
    lassign [scope_rows $v $p sequential_assertions] assertion keep
    sequential_expect $r $assertion {
        label_span lab colon_span : assert_span assert condition_span {a <= b}
        report_keyword_span report report_span {"message"} severity_keyword_span severity
        severity_span warning semicolon_span {;} span {lab: assert a <= b report "message" severity warning;}
    }
    sequential_expect $r $keep {label_span keep span {keep: assert true;}}
    check direct_complete complete [scope_complete $v $p sequential_assertions]
    check subtree_partial partial [dict get [::vhdl_index::query::subtree $v $p sequential_assertions] completeness]
    check subtree_rows 2 [llength [dict get [::vhdl_index::query::subtree $v $a sequential_assertions] rows]]
    sequential_expect $r [lindex [scope_rows $v $p report_statements] 0] {
        report_keyword_span report report_span {"status"} severity_span note label_span msg
    }
    sequential_expect $r [lindex [scope_rows $v $p null_statements] 0] {null_span null span {idle: null;}}
    lassign [scope_rows $v $p wait_statements] bare wait
    sequential_expect $r $bare {span {wait;}}
    check bare_list {} [dict get $bare sensitivity_name_spans]
    sequential_expect $r $wait {wait_span wait label_span sync on_span on until_span until
        condition_span {a <= b} for_span for timeout_span {1 ns}}
    check wait_names {a {b(1 to 2)} r.member} [lmap_spans $r [dict get $wait sensitivity_name_spans]]
    check owner $p [dict get $wait owner_occurrence_id]
    check snapshot [dict get $r source_id] [lindex [dict get $wait occurrence_id] 0]
    scope_integrity $r $v
}

foreach {input capability code} {
    {assert report "missing";} sequential_assertions SEQUENTIAL_ASSERTION_MISSING_CONDITION
    {assert a report ;} sequential_assertions SEQUENTIAL_ASSERTION_MISSING_REPORT
    {assert a severity ;} sequential_assertions SEQUENTIAL_ASSERTION_MISSING_SEVERITY
    {report severity note;} report_statements SEQUENTIAL_REPORT_MISSING_REPORT
    {report "x" severity ;} report_statements SEQUENTIAL_REPORT_MISSING_SEVERITY
    {wait on ;} wait_statements SEQUENTIAL_WAIT_MISSING_NAME
    {wait on all;} wait_statements SEQUENTIAL_WAIT_MISSING_TARGET
    {wait until ;} wait_statements SEQUENTIAL_WAIT_MISSING_CONDITION
    {wait for ;} wait_statements SEQUENTIAL_WAIT_MISSING_TIMEOUT
    {wait for 1 ns until a;} wait_statements SEQUENTIAL_WAIT_CLAUSE_ORDER
    {wait until a until b;} wait_statements SEQUENTIAL_WAIT_CLAUSE_ORDER
    {postponed wait;} wait_statements SEQUENTIAL_WAIT_ILLEGAL_MODIFIER
    {wait on a} wait_statements MISSING_SEMICOLON
} {
    set r [sequential_input "before: null; $input afterward: null;"]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    set row [lindex [scope_rows $v $p $capability] 0]
    check malformed malformed [dict get $row status]
    check code $code [dict get [lindex [dict get $row diagnostics] 0] code]
    check partial partial [scope_complete $v $p $capability]
    check sibling_labels {before afterward} [lmap_labels [scope_rows $v $p null_statements]]
    scope_integrity $r $v
}
puts {Sequential leaves, wait and opaque control-flow assertions passed}
