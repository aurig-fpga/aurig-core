# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

proc control_input {body {edition 2008} {limits {}}} {
    scope_input "entity e is end; architecture a of e is begin p: process begin $body end process p; end;" $edition $limits
}
proc control_fields {r row fields} {
    foreach {key expected} $fields {
        set span [dict get $row $key]
        check $key $expected [expr {$span eq {} ? {} : [surface $r $span]}]
    }
}
proc control_subtree {v id cap {expect complete}} {
    set outcome [::vhdl_index::query::subtree $v $id $cap]
    check "$cap subtree coverage" $expect [dict get $outcome completeness]
    return [dict get $outcome rows]
}

foreach edition {1993 2002 2008} {
    set r [control_input {direct: null;
        \If Label\: if test_fn("then", (1 + 2)) then
            inner: if ready then inside: null; end if inner;
        elsif second then
        elsif third then work(ready => true);
        else report "end if;"; end if \If Label\;
        if done then end if;
        after_if: null;} $edition]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    lassign [scope_rows $v $p control_flow_envelopes] row empty
    check control_kind if [dict get $row kind]
    check structured structured [dict get $row interior_status]
    set label [format {%cIf Label%c} 92 92]
    control_fields $r $row [list label_span $label colon_span : opener_span if end_keyword_span end \
        end_kind_span if end_label_span $label semicolon_span {;} terminator_span "end if ${label};"]
    check alternatives 4 [llength [dict get $row alternative_owner_ids]]
    set alternatives {}
    foreach id [dict get $row alternative_owner_ids] {
        set owner [::vhdl_index::regions::region $v $id]
        check nearest_owner $p [dict get $owner parent_id]
        check separate_inventory not_applicable [scope_complete $v $id object_declarations]
        check control_link [dict get $row occurrence_id] [dict get $owner control_occurrence_id]
        lappend alternatives [dict get $owner syntax]
    }
    lassign $alternatives first second third last
    control_fields $r $first {keyword_span if condition_span {test_fn("then", (1 + 2))} connector_span then}
    control_fields $r $second {keyword_span elsif condition_span second connector_span then}
    control_fields $r $third {keyword_span elsif condition_span third connector_span then}
    control_fields $r $last {keyword_span else condition_span {} connector_span {}}
    set secondId [lindex [dict get $row alternative_owner_ids] 1]
    check verified_empty complete [scope_complete $v $secondId null_statements]
    check verified_empty_rows {} [scope_rows $v $secondId null_statements]
    check direct_nulls 2 [llength [scope_rows $v $p null_statements]]
    set labels {}
    foreach item [control_subtree $v $p null_statements] {lappend labels [dict get $item label]}
    check subtree_order {direct inside after_if} $labels
    check controls 3 [llength [control_subtree $v $p control_flow_envelopes]]
    check empty_if 1 [llength [dict get $empty alternative_owner_ids]]
    scope_integrity $r $v
}

foreach {body expected} {
    {if then first: null; elsif ok then good: null; end if; after_if: null;} {first good after_if}
    {if bad; elsif ok then good: null; end if; after_if: null;} {good after_if}
    {if ok then good: null; else last: null; elsif late then lost: null; else lost_again: null; end if; after_if: null;} {good last after_if}
} {
    set r [control_input $body]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    check control_coverage partial [scope_complete $v $p control_flow_envelopes]
    set completion [expr {[lindex $expected 0] eq "first" ? "complete" : "partial"}]
    set labels {}
    foreach item [control_subtree $v $p null_statements $completion] {lappend labels [dict get $item label]}
    check local_recovery $expected $labels
    scope_integrity $r $v
}
puts {If alternatives and nested sequential ownership assertions passed}

proc lmap_control_spans {r spans} {
    set text {}
    foreach span $spans {lappend text [surface $r $span]}
    return $text
}

foreach {edition opening closing} {1993 {} {} 2002 {} {} 2008 {} {} 2008 ? ?} {
    set r [control_input "pick: case $opening pick_fn(1, 2) is
        when 0 | 1 to 3 | ((1 => 2, 2 => 4)) => inside: null;
        when others =>
        end case $closing pick; after_case: null;" $edition]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    set row [lindex [scope_rows $v $p control_flow_envelopes] 0]
    check case_kind case [dict get $row kind]
    control_fields $r $row [list opener_span case matching_span $opening selector_span {pick_fn(1, 2)} \
        is_span is end_kind_span case end_matching_span $closing end_label_span pick semicolon_span {;}]
    lassign [dict get $row alternative_owner_ids] one two
    set first [scope_shape $v $one]
    set last [scope_shape $v $two]
    control_fields $r $first {keyword_span when arrow_span =>}
    check choices {0 {1 to 3} {((1 => 2, 2 => 4))}} [choice_surfaces $r [dict get $first choices]]
    check separators {| |} [lmap_control_spans $r [dict get $first choice_separator_spans]]
    check others others [dict get [lindex [dict get $last choices] 0] kind]
    check empty complete [scope_complete $v $two null_statements]
    check case_subtree 2 [llength [control_subtree $v $p null_statements]]
    scope_integrity $r $v
}

foreach {body diagnostic expected} {
    {case is when others => ok: null; end case; last: null;} INCOMPLETE_BRANCH_HEADER {ok last}
    {case key when others => ok: null; end case; last: null;} INCOMPLETE_BRANCH_HEADER {ok last}
    {case key is end case; last: null;} CASE_EXPECTED_WHEN {last}
    {case key is when | 1 | => ok: null; end case; last: null;} CASE_MISSING_CHOICE {ok last}
    {case key is when 0 lost: null; when others => ok: null; end case; last: null;} CASE_MISSING_ARROW {ok last}
    {case ? flag is when others => ok: null; end case; last: null;} MISMATCHED_CASE_MARKER {ok last}
    {case flag is when others => ok: null; end case ?; last: null;} MISMATCHED_CASE_MARKER {ok last}
    {case ? ? flag is when others => ok: null; end case ? ?; last: null;} DUPLICATE_CASE_MARKER {ok last}
} {
    set r [control_input $body]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    check case_diagnostic $diagnostic [scope_error $r]
    check case_coverage partial [scope_complete $v $p control_flow_envelopes]
    set expectedCoverage [expr {$diagnostic eq "CASE_MISSING_ARROW" ? "partial" : "complete"}]
    set labels {}
    foreach item [control_subtree $v $p null_statements $expectedCoverage] {lappend labels [dict get $item label]}
    check case_recovery $expected $labels
    scope_integrity $r $v
}
puts {Case choices, matching markers and recovery assertions passed}

foreach edition {1993 2002 2008} {
    set r [control_input {outer: for \Unused Param\ in 1 to 3 loop null; end loop outer;
        while ready(1) loop next outer when done; end loop;
        loop exit when done; end loop;
        for j in pkg.index_type loop end loop;
        for k in obj.member'range(1) loop end loop;} $edition]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    set forms {}
    foreach row [scope_rows $v $p control_flow_envelopes] {
        lappend forms [dict get $row iteration_kind]
        control_fields $r $row {loop_span loop end_kind_span loop}
        set id [dict get $row body_owner_id]
        check loop_link [dict get $row occurrence_id] [dict get [::vhdl_index::regions::region $v $id] control_occurrence_id]
        check objects_not_applicable not_applicable [scope_complete $v $id object_declarations]
    }
    check forms {for while unconditional for for} $forms
    lassign [control_subtree $v $p loop_parameters] one two three
    control_fields $r $one {in_span in}
    check parameter_role loop_parameter [lindex [dict get $one occurrence_id] 1]
    check direction to [dict get $one range direction]
    control_fields $r [dict get $two range] {type_mark_span pkg.index_type}
    control_fields $r [dict get $three range] {range_attribute_span {obj.member'range(1)}}
    control_fields $r [lindex [control_subtree $v $p next_statements] 0] {loop_label_span outer condition_span done}
    check retained_null 1 [llength [control_subtree $v $p null_statements]]
    scope_integrity $r $v
}

foreach {body diagnostic completion expected} {
    {while loop carried: null; end loop; after_loop: null;} INCOMPLETE_BRANCH_HEADER complete {carried after_loop}
    {for in 1 to 2 loop carried: null; end loop; after_loop: null;} LOOP_EXPECTED_PARAMETER complete {carried after_loop}
    {for i 1 to 2 loop carried: null; end loop; after_loop: null;} LOOP_EXPECTED_IN complete {carried after_loop}
    {for i in loop carried: null; end loop; after_loop: null;} INCOMPLETE_BRANCH_HEADER complete {carried after_loop}
    {for i in 1 to 2 lost: null; end loop; after_loop: null;} INCOMPLETE_BRANCH_HEADER partial {after_loop}
} {
    set r [control_input $body]
    set v [::vhdl_index::regions::view $r]
    set p [scope_find $v process p:]
    check loop_diagnostic $diagnostic [scope_error $r]
    check loop_coverage partial [scope_complete $v $p control_flow_envelopes]
    set labels {}
    foreach item [control_subtree $v $p null_statements $completion] {lappend labels [dict get $item label]}
    check loop_recovery $expected $labels
    scope_integrity $r $v
}

set r [scope_input {entity e is end;
    architecture a of e is
        function f return boolean is begin if true then loop return; end loop; end if; end function;
        procedure pr is begin case 0 is when others => if true then return 1; end if; end case; end procedure;
    begin p: process begin for i in 0 to 1 loop return; end loop; end process; end;}]
set v [::vhdl_index::regions::view $r]
foreach {kind prefix expected} {
    function {function f} RETURN_FUNCTION_MISSING_EXPRESSION
    procedure {procedure pr} RETURN_PROCEDURE_UNEXPECTED_EXPRESSION
    process p: RETURN_OUTSIDE_SUBPROGRAM
} {
    set owner [scope_find $v $kind $prefix]
    check direct_returns {} [scope_rows $v $owner return_statements]
    set row [lindex [control_subtree $v $owner return_statements] 0]
    check context $expected [dict get [lindex [dict get $row context_diagnostics] 0] code]
}
scope_integrity $r $v
puts {Loop schemes, parameter roles and enclosing body context assertions passed}
