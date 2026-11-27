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

set r [scope_input {entity e is end;
    architecture a of e is
        procedure helper is begin return; end procedure;
        function f return integer is
            procedure nested is begin return 12; end;
        begin
            return f2(1, 2);
            return;
        end function;
    begin
        p: process begin
            call_label: pkg.helper(1, mode => my_fn(2, 3), value => open);
            bare: helper;
            indexed: inst(1).step(v => a);
            bad: helper(missing => , good => 2, other => inertial v);
            n: next main when a <= b;
            exit;
            bad_exit: exit when ;
            return;
        end process;
    end;}]
set v [::vhdl_index::regions::view $r]
set p [scope_find $v process p:]
set f [scope_find $v function {function f}]
set nested [scope_find $v procedure {procedure nested}]
lassign [scope_rows $v $p sequential_procedure_calls] named bare indexed malformed
sequential_expect $r $named {label_span call_label called_name_span pkg.helper semicolon_span {;}}
sequential_expect $r $bare {label_span bare called_name_span helper}
sequential_expect $r $indexed {called_name_span {inst(1).step}}
check parameter_commas {, ,} [lmap_spans $r [dict get $named actual_parameters separator_spans]]
set actuals [scope_rows $v $p sequential_actual_parameter_associations]
check actual_count 5 [llength $actuals]
check owner $p [dict get [lindex $actuals 0] owner_occurrence_id]
check call_identity [dict get $named occurrence_id] [dict get [lindex $actuals 0] call_occurrence_id]
sequential_expect $r [lindex $actuals 1] {formal_span mode arrow_span => actual_span {my_fn(2, 3)}}
sequential_expect $r [lindex $actuals 2] {formal_span value actual_span open}
check actual_partial partial [scope_complete $v $p sequential_actual_parameter_associations]
check map_rows {} [scope_rows $v $p map_associations]
check concurrent_actual_rows {} [scope_rows $v $p actual_parameter_associations]
check call_malformed malformed [dict get $malformed status]
check call_recovered_actuals 1 [llength [dict get $malformed actual_parameters associations]]
sequential_expect $r [lindex [scope_rows $v $p next_statements] 0] {
    label_span n next_span next loop_label_span main when_span when condition_span {a <= b}
}
lassign [scope_rows $v $p exit_statements] exit bad
sequential_expect $r $exit {exit_span exit semicolon_span {;}}
check missing_exit_payload SEQUENTIAL_EXIT_MISSING_CONDITION [dict get [lindex [dict get $bad diagnostics] 0] code]
lassign [scope_rows $v $f return_statements] value bare
sequential_expect $r $value {return_span return expression_span {f2(1, 2)}}
check function_bare_grammar parsed [dict get $bare status]
check function_bare_context RETURN_FUNCTION_MISSING_EXPRESSION [dict get [lindex [dict get $bare context_diagnostics] 0] code]
set out [lindex [scope_rows $v $nested return_statements] 0]
check procedure_value_context RETURN_PROCEDURE_UNEXPECTED_EXPRESSION [dict get [lindex [dict get $out context_diagnostics] 0] code]
check subtree_returns 3 [llength [dict get [::vhdl_index::query::subtree $v $f return_statements] rows]]
scope_integrity $r $v
puts {Sequential call, return, next and exit assertions passed}
