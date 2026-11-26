# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

foreach edition {1993 2002 2008} {
    set r [scope_input {entity e is end; architecture a of e is begin
        s: postponed target(0).part(7 downto 4) <= guarded reject f(1, 2) inertial
             value(0, 1) after 5 ns, null after 10 ns;
        (x, y) <= transport (1, 2);
        x <= inertial unaffected when flag else f("when", 'X') after delay when ready;
        with choose(1, 2) select y <= p, q after 2 ns when 1 | 2, unaffected when others;
        no_actuals;
        u: component c;
    end;} $edition]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set rows [scope_rows $v $a concurrent_signal_assignments]
    check assignment_count 4 [llength $rows]
    check complete complete [scope_complete $v $a concurrent_signal_assignments]
    lassign $rows simple aggregate conditional selected
    foreach {key expected} {
        label_span s postponed_span postponed target_span {target(0).part(7 downto 4)}
        operator_span <= guarded_span guarded terminator_span {;}
    } {
        check $key $expected [surface $r [dict get $simple $key]]
    }
    check simple simple [dict get $simple category]
    check simple_owner $a [dict get $simple owner_occurrence_id]
    set delay [dict get $simple delay]
    check inertial inertial [surface $r [dict get $delay keyword_span]]
    check reject f(1,\ 2) [surface $r [dict get $delay reject_time_span]]
    set wave [lindex [dict get $simple alternatives] 0]
    lassign [dict get $wave elements] elem null
    check first_value {value(0, 1)} [surface $r [dict get $elem value_span]]
    check first_delay {5 ns} [surface $r [dict get $elem delay_span]]
    check after after [surface $r [dict get $elem after_span]]
    check null_kind null [dict get $null kind]
    check element_separator , [surface $r [lindex [dict get $wave element_separator_spans] 0]]
    check aggregate aggregate [dict get $aggregate target kind]
    check transport transport [surface $r [dict get $aggregate delay keyword_span]]
    check conditional conditional [dict get $conditional category]
    lassign [dict get $conditional alternatives] first second
    check unaffected unaffected [surface $r [dict get $first unaffected_span]]
    check condition flag [surface $r [dict get $first condition_span]]
    check else else [surface $r [dict get $first else_span]]
    check final_condition ready [surface $r [dict get $second condition_span]]
    check selected selected [dict get $selected category]
    check selector {choose(1, 2)} [surface $r [dict get $selected selector_span]]
    check select select [surface $r [dict get $selected select_span]]
    lassign [dict get $selected alternatives] first second
    check choice_count 2 [llength [dict get $first choices]]
    check element_count 2 [llength [dict get $first elements]]
    check choices {1 2} [choice_surfaces $r [dict get $first choices]]
    check choice_bar | [surface $r [lindex [dict get $first choice_separator_spans] 0]]
    check alternative_comma , [surface $r [dict get $first alternative_separator_span]]
    check others others [dict get [lindex [dict get $second choices] 0] kind]
    check calls 1 [llength [scope_rows $v $a concurrent_procedure_calls]]
    check instances 1 [llength [scope_rows $v $a instantiations]]
    scope_integrity $r $v
}
foreach {bad code edition} {
    {<= 1;} SIGNAL_ASSIGNMENT_MISSING_TARGET 2008
    {with x select <= a when others;} SIGNAL_ASSIGNMENT_MISSING_TARGET 2008
    {with x select y a when others;} SIGNAL_ASSIGNMENT_EXPECTED_OPERATOR 2008
    {with x select ? y <= a when others;} EDITION_MATCHING_SELECTION 1993
    {x <= ;} SIGNAL_ASSIGNMENT_MISSING_WAVEFORM 2008
    {x <= y after ;} SIGNAL_ASSIGNMENT_MISSING_AFTER_TIME 2008
    {x <= a when else b;} SIGNAL_ASSIGNMENT_MISSING_CONDITION 2008
    {x <= a when c else ;} SIGNAL_ASSIGNMENT_MISSING_WAVEFORM 2008
    {x <= reject inertial a;} SIGNAL_ASSIGNMENT_MISSING_REJECT_TIME 2008
    {x <= force a;} SIGNAL_ASSIGNMENT_CONCURRENT_FORCE_RELEASE 2008
    {with x select y <= a when 0 | , b when others;} SIGNAL_ASSIGNMENT_MISSING_CHOICE 2008
    {with x select y <= a when others, b when 0;} SIGNAL_ASSIGNMENT_OTHERS_MUST_BE_FINAL 2008
    {x <= f(1,2)} SIGNAL_ASSIGNMENT_EXPECTED_SEMICOLON 2008
} {
    set r [scope_input "entity e is end; architecture a of e is begin $bad keep: component c; x <= unaffected; end;" $edition]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set d [::vhdl_index::query::direct $v $a concurrent_signal_assignments]
    check partial partial [dict get $d completeness]
    set proof [lindex [dict get $d evidence] 0]
    check diagnostic $code [dict get [lindex [dict get $proof diagnostics] 0] code]
    check safe_assignment 1 [llength [dict get $d rows]]
    check safe_instance 1 [llength [scope_rows $v $a instantiations]]
    scope_integrity $r $v
}

set r [scope_input {entity e is begin x <= y; end;
architecture a of e is begin postponed with s select ? x <= y when others; end;}]
set v [::vhdl_index::regions::view $r]
set e [scope_find $v entity {entity e}]
set a [scope_find $v architecture {architecture a}]
check entity none [expr {[llength [scope_rows $v $e concurrent_signal_assignments]] == 0 ? "none" : "assignment"}]
check matching ? [surface $r [dict get [lindex [scope_rows $v $a concurrent_signal_assignments] 0] matching_span]]
scope_integrity $r $v
puts {Concurrent signal assignment assertions passed}
