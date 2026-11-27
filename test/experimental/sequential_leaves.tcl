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
    check subtree_complete complete [dict get [::vhdl_index::query::subtree $v $p sequential_assertions] completeness]
    check subtree_rows 3 [llength [dict get [::vhdl_index::query::subtree $v $a sequential_assertions] rows]]
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
    {wait for guarded;} wait_statements SEQUENTIAL_WAIT_INVALID_PAYLOAD_START
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
puts {Sequential leaves, wait and scoped control-flow assertions passed}

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

foreach edition {1993 2002 2008} {
    set r [sequential_input {v: idx(1, f(2, 3)) := a <= b;
        (lo, hi) := (1, 2);
        w: word(3 downto 1) <= reject 1 ns inertial x after 2 ns, null after 3 ns;
        word <= unaffected;} $edition]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    lassign [scope_rows $v $p variable_assignments] variable aggregate
    sequential_expect $r $variable {label_span v target_span {idx(1, f(2, 3))} operator_span := expression_span {a <= b}}
    check aggregate aggregate [dict get $aggregate target kind]
    lassign [scope_rows $v $p sequential_signal_assignments] waveform unaffected
    sequential_expect $r $waveform {label_span w target_span {word(3 downto 1)} operator_span <=
        waveform_span {x after 2 ns, null after 3 ns}}
    sequential_expect $r [dict get $waveform delay] {keyword_span inertial reject_time_span {1 ns}}
    set wave [lindex [dict get $waveform alternatives] 0]
    check multi_element 2 [llength [dict get $wave elements]]
    sequential_expect $r [lindex [dict get $wave elements] 1] {value_span null delay_span {3 ns}}
    sequential_expect $r $unaffected {waveform_span unaffected}
    check name_call_collision {} [scope_rows $v $p sequential_procedure_calls]
    scope_integrity $r $v
}

set edition_forms {v := a when x else b when y else c;
    with a <= b select ? v := f(1, 2) when 0 | 1, b when others;
    s <= transport a after 1 ns, b after 2 ns when flag else unaffected;
    with k select s <= a, b when 0, c when others;
    s <= force in a;
    s <= force out a when c else b;
    with k select s <= force a when 0, b when others;
    s <= release out;}
foreach edition {1993 2002 2008} {
    set r [sequential_input $edition_forms $edition]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    check variable_forms 2 [llength [scope_rows $v $p variable_assignments]]
    check signal_forms 6 [llength [scope_rows $v $p sequential_signal_assignments]]
    lassign [scope_rows $v $p variable_assignments] conditional selected
    lassign [scope_rows $v $p sequential_signal_assignments] conditional_wave selected_wave force force_if force_sel release
    if {$edition == 2008} {
        foreach {row form} [list $conditional conditional $selected selected $conditional_wave conditional \
            $selected_wave selected $force simple $force_if conditional $force_sel selected $release simple] {
            check grammar parsed [dict get $row status]
            check form $form [dict get $row category]
        }
        check alternatives 3 [llength [dict get $conditional alternatives]]
        sequential_expect $r $selected {with_span with selector_span {a <= b} select_span select matching_span ?}
        set choice [lindex [dict get $selected alternatives] 0]
        check bars {|} [lmap_spans $r [dict get $choice choice_separator_spans]]
        sequential_expect $r $choice {expression_span {f(1, 2)} when_span when alternative_separator_span ,}
        check selected_wave_comma 2 [llength [dict get [lindex [dict get $selected_wave alternatives] 0] elements]]
        sequential_expect $r $force {force_span force force_mode_span in expression_span a}
        sequential_expect $r $release {release_span release force_mode_span out span {s <= release out;}}
    } else {
        foreach row [concat [scope_rows $v $p variable_assignments] [scope_rows $v $p sequential_signal_assignments]] {
            check edition malformed [dict get $row status]
            set codes {}
            foreach issue [dict get $row diagnostics] {lappend codes [dict get $issue code]}
            check edition_diagnostic 1 [string match EDITION_SEQUENTIAL_* [lindex $codes 0]]
        }
    }
    scope_integrity $r $v
}
puts {Sequential assignment forms and edition assertions passed}

foreach {input capability code} {
    {<= 1;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_MISSING_TARGET
    {:= 1;} variable_assignments VARIABLE_ASSIGNMENT_MISSING_TARGET
    {a := ;} variable_assignments VARIABLE_ASSIGNMENT_MISSING_EXPRESSION
    {a <= ;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_MISSING_WAVEFORM
    {a <= x, ;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_MISSING_WAVEFORM
    {a <= x after ;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_MISSING_AFTER_TIME
    {a <= x when ;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_MISSING_CONDITION
    {a := x when y else ;} variable_assignments VARIABLE_ASSIGNMENT_MISSING_EXPRESSION
    {with x select a := v when ;} variable_assignments VARIABLE_ASSIGNMENT_MISSING_CHOICE
    {with x select a <= v when 0, ;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_MISSING_WAVEFORM
    {a <= guarded x;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_ILLEGAL_MODIFIER
    {a <= transport release;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_ILLEGAL_MODIFIER
    {a <= release in when x;} sequential_signal_assignments SEQUENTIAL_SIGNAL_ASSIGNMENT_INVALID_RELEASE
    {next t when ;} next_statements SEQUENTIAL_NEXT_MISSING_CONDITION
    {exit foo bar;} exit_statements SEQUENTIAL_EXIT_UNEXPECTED_TOKEN
    {assert a next when b;} sequential_assertions MISSING_SEMICOLON
    {x := foo(1, 2) wait;} variable_assignments MISSING_SEMICOLON
    {x <= y v := 3;} sequential_signal_assignments MISSING_SEMICOLON
    {null helper;} null_statements MISSING_SEMICOLON
} {
    set r [sequential_input "$input survivor: report \"still owned\";"]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    set bad [lindex [scope_rows $v $p $capability] 0]
    check malformed malformed [dict get $bad status]
    check code $code [dict get [lindex [dict get $bad diagnostics] 0] code]
    check report_recovery survivor [dict get [lindex [scope_rows $v $p report_statements] 0] label]
    scope_integrity $r $v
}

set r [sequential_input {a: null; wrong: if flag then loop null; end loop; end if stray; z: null;
    unknown[integer](1); call_it;}]
set v [::vhdl_index::regions::view $r]
set p [scope_find $v process p:]
check siblings {a z} [lmap_labels [scope_rows $v $p null_statements]]
check malformed_control malformed [dict get [lindex [scope_rows $v $p control_flow_envelopes] 0] status]
check verified_empty complete [scope_complete $v $p wait_statements]
check nested_empty complete [dict get [::vhdl_index::query::subtree $v $p wait_statements] completeness]
check unsupported_calls partial [scope_complete $v $p sequential_procedure_calls]
check known_call 1 [llength [scope_rows $v $p sequential_procedure_calls]]
set gap [scope_find $v sequential_statement {unknown[}]
check unsupported unsupported [dict get [::vhdl_index::regions::region $v $gap] availability]
scope_integrity $r $v

foreach {input limits code} {
    {outer: if a then inner: if b then null; end if outer; end if;} {} ANCESTOR_END_NAME
    {if a then loop null; end if;} {} MISMATCHED_END_KIND
    {if a then if b then null; end if; end if;} {scopes 2} SCOPE_LIMIT
    {helper(f(g(1)));} {delimiters 2} DELIMITER_LIMIT
} {
    set r [sequential_input $input 2008 $limits]
    set v [::vhdl_index::regions::view $r]
    check unproven $code [scope_error $r]
    set p [scope_find $v process p:]
    check withdrawn withdrawn [dict get [::vhdl_index::regions::region $v $p] availability]
    check withdrawn_rows {} [scope_rows $v $p null_statements]
    check withheld unavailable [scope_complete $v $p null_statements]
    scope_integrity $r $v
}

set r [scope_input {entity e is end; architecture a of e is
    function lost return boolean is begin return true; end function wrong;
    procedure keep is begin null; end procedure;
begin
    lost_p: process begin assert true; end process wrong;
    keep_p: process begin assert false; end process;
end;}]
set v [::vhdl_index::regions::view $r]
foreach {kind name cap} {
    function {function lost} return_statements process lost_p: sequential_assertions
} {
    set owner [scope_find $v $kind $name]
    check withdrawn unavailable [scope_complete $v $owner $cap]
    check no_rows {} [scope_rows $v $owner $cap]
}
set keeper [scope_find $v process keep_p:]
check safe_process 1 [llength [scope_rows $v $keeper sequential_assertions]]
set arch [scope_find $v architecture {architecture a}]
check mixed_subtree partial [dict get [::vhdl_index::query::subtree $v $arch sequential_assertions] completeness]
scope_integrity $r $v

set r [scope_input {package p is
    type t is protected procedure run; end protected;
end;
package body p is
    type t is protected body
        procedure run is begin assert true; end procedure;
    end protected body;
end package body;} 2002]
set v [::vhdl_index::regions::view $r]
set member [scope_find $v procedure {procedure run is}]
check protected_assertion 1 [llength [scope_rows $v $member sequential_assertions]]
scope_integrity $r $v

foreach {fixture edition counts} {
    sequential_common 1993 {1 1 1 1}
    sequential_common 2002 {1 1 1 1}
    sequential_common 2008 {1 1 1 1}
    sequential_2008 2008 {2 6 0 0}
} {
    set r [::vhdl_index::analyze_file [file join $tests fixtures $fixture.vhd.fixture] $edition]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process {p :}]
    foreach cap {variable_assignments sequential_signal_assignments sequential_procedure_calls control_flow_envelopes} count $counts {
        check fixture_count $count [llength [scope_rows $v $p $cap]]
        check fixture_grammar complete [scope_complete $v $p $cap]
    }
    scope_integrity $r $v
}
puts {Sequential recovery, withdrawal and fixture isolation assertions passed}

# Truncated and token-limited bodies cannot publish earlier buffered leaves.
foreach {limit source tailCode} {
    {} {entity e is end; architecture a of e is begin p: process begin null; assert b} TRUNCATED_SCOPE
    {tokens 30} {entity e is end; architecture a of e is begin p: process begin null; wait for 2 ns; report "more"; end process; end;} TOKEN_LIMIT
} {
    set r [scope_input $source 2008 $limit]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    check unavailable unavailable [scope_complete $v $p null_statements]
    check no_premature_publication {} [scope_rows $v $p null_statements]
    set diagnostics [concat [dict get $r lexical_diagnostics] [dict get $r structural_diagnostics]]
    set codes {}
    foreach diagnostic $diagnostics {lappend codes [dict get $diagnostic code]}
    check loss_diagnostic 1 [expr {$tailCode in $codes}]
    scope_integrity $r $v

    set text {}
    set starts [dict get $r tape starts]
    set last [lindex $starts 0]
    foreach start [lrange $starts 1 end] {
        append text [surface $r [list $last $start]]
        set last $start
    }
    check tape_reconstruction $source $text
}

set r [sequential_input {unexpected. + junk; null;}]
set v [::vhdl_index::regions::view $r]
set p [scope_find $v process p:]
set gap [scope_find $v sequential_statement unexpected]
check uncertain uncertain [dict get [::vhdl_index::regions::region $v $gap] availability]
check uncertain_inventory partial [scope_complete $v $p variable_assignments]
check bounded_null 1 [llength [scope_rows $v $p null_statements]]
