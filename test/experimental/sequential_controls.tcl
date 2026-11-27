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
