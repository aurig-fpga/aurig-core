# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

proc count_subtree {view owner capability} {
    llength [dict get [::vhdl_index::query::subtree $view $owner $capability] rows]
}
proc concurrent_invariants {result view} {
    scope_integrity $result $view
    set tape [dict get $result tape]
    set previous 0
    foreach last [lrange [dict get $tape starts] 1 end] {
        check token_progress 1 [expr {$last >= $previous}]
        set previous $last
    }
    check token_extent [dict get $result snapshot length] $previous
    dict for {key rows} [dict get $result concurrent_statements] {
        lassign $key offset family
        set id [::vhdl_index::regions::identity $view [list region $offset]]
        set region [::vhdl_index::regions::region $view $id]
        check owner_proved proved [dict get $region availability]
        lassign [dict get $region span] a b
        set last $a
        foreach row $rows {
            lassign [dict get $row span] x y
            check owned_order 1 [expr {$a <= $x && $last <= $x && $x < $y && $y <= $b}]
            set last $y
        }
    }
}

foreach {name editions expected} {
    ordinary {1993 2002 2008} {1 2 2 3 1 1}
    modern {2008} {0 2 0 1 1 1}
} {
    foreach edition $editions {
        set path [file join $tests fixtures "${name}-concurrent.vhd.fixture"]
        set r [::vhdl_index::analyze_file $path $edition]
        set v [::vhdl_index::regions::view $r]
        set e [scope_find $v entity "entity ${name}_concurrent"]
        set a [scope_find $v architecture {architecture rtl}]
        lassign $expected entityCalls assertions calls assignments processes sensitivities
        check entity_calls $entityCalls [count_subtree $v $e concurrent_procedure_calls]
        foreach {family expectedCount} [list concurrent_assertions $assertions concurrent_procedure_calls $calls \
            concurrent_signal_assignments $assignments process_headers $processes sensitivity_lists $sensitivities] {
            set out [::vhdl_index::query::subtree $v $a $family]
            # The assertion count for ordinary includes the entity's assertion.
            set count [llength [dict get $out rows]]
            if {$family eq "concurrent_assertions"} {incr count [count_subtree $v $e $family]}
            check $family $expectedCount $count
            if {$expectedCount} {check completeness complete [dict get $out completeness]}
        }
        check structural_diagnostics {} [dict get $r structural_diagnostics]
        concurrent_invariants $r $v
    }
}

set r [::vhdl_index::analyze_file [file join $tests fixtures malformed-concurrent.vhd.fixture] 2008]
set v [::vhdl_index::regions::view $r]
set a [scope_find $v architecture {architecture rtl}]
foreach {family state rows} {
    concurrent_assertions partial 1 concurrent_procedure_calls complete 1
    concurrent_signal_assignments partial 0 actual_parameter_associations partial 1
    process_headers complete 1 sensitivity_lists partial 1
    instantiations complete 0 map_associations complete 0
} {
    check $family $state [scope_complete $v $a $family]
    check rows $rows [llength [scope_rows $v $a $family]]
}
concurrent_invariants $r $v

set r [scope_input {entity e is end; architecture a of e is
    component c generic (package p is new work.g generic map (1)); end component wrong;
begin
    lost: if first: true generate
        u: component c port map (open);
        maybe: worker;
        assert true;
        foo(1, x => 2);
        x <= unaffected;
        p: process (x) begin null; end process wrong;
        begin_withdraw: block begin
            assert true;
            foo(3);
            x <= '1';
            pp: process(all) begin null; end process;
        end block;
    end wrong;
    else safe: generate
        saved: assert true;
        foo(4);
        x <= '0';
        po: process(all) begin null; end process;
    end safe;
    end generate;
    saved: component c;
end;}]
set v [::vhdl_index::regions::view $r]
set a [scope_find $v architecture {architecture a}]
set lost [scope_find $v generate_alternative {if first:}]
set safe [scope_find $v generate_alternative {else safe:}]
foreach family {concurrent_assertions concurrent_procedure_calls concurrent_signal_assignments
    actual_parameter_associations process_headers sensitivity_lists} {
    check architecture_direct_empty complete [scope_complete $v $a $family]
    check safe_complete complete [scope_complete $v $safe $family]
    check lost_unavailable unavailable [scope_complete $v $lost $family]
    set out [::vhdl_index::query::subtree $v $a $family]
    check subtree_partial partial [dict get $out completeness]
    check only_safe 1 [llength [dict get $out rows]]
    check safe_owner $safe [dict get [lindex [dict get $out rows] 0] owner_occurrence_id]
}
check r1_map_evidence partial [scope_complete $v $a map_associations]
check safe_instance 1 [llength [scope_rows $v $a instantiations]]
concurrent_invariants $r $v

set r [scope_input {entity e is end; architecture a of e is begin
    b: block begin
        assert true
        p: process begin null; end process;
    end block;
    f: for i in 0 to 1 generate
        x <= unaffected
        g: if false generate assert false; end generate;
    end generate;
    g: case 0 generate
        when first: 0 => x <= '1'
        when second: others => assert true;
    end generate;
    report "unknown concurrent form";
    keep: component c;
end;}]
set v [::vhdl_index::regions::view $r]
set a [scope_find $v architecture {architecture a}]
set b [scope_find $v block b:]
set f [scope_find $v for_generate f:]
set first [scope_find $v generate_alternative {when first:}]
set second [scope_find $v generate_alternative {when second:}]
check root_complete {} [dict get $r recovery]
check unknown_is_partial partial [scope_complete $v $a concurrent_procedure_calls]
check unknown_is_partial partial [scope_complete $v $a map_associations]
check block_assertion_partial partial [scope_complete $v $b concurrent_assertions]
check block_sibling 1 [llength [scope_rows $v $b process_headers]]
check for_assignment_partial partial [scope_complete $v $f concurrent_signal_assignments]
check case_assignment_partial partial [scope_complete $v $first concurrent_signal_assignments]
check case_sibling 1 [llength [scope_rows $v $second concurrent_assertions]]
check safe_instance 1 [llength [scope_rows $v $a instantiations]]
concurrent_invariants $r $v

foreach {body limits} {
    {assert f(g(h(x)));} {delimiters 2}
    {q: process begin wait; end process;} {scopes 1}
    {assert true; p(2); q: process(all) begin null; end process;} {tokens 12}
    {p: process (x) begin null; end block;} {}
    {x <= y unlabelled(1); keep: component c;} {}
    {x <= unaffected unlabelled(1); keep: component c;} {}
    {u: component c unlabelled(1); keep: component c;} {}
} {
    set r [scope_input "entity e is end; architecture a of e is begin assert true; $body end;" 2008 $limits]
    set v [::vhdl_index::regions::view $r]
    check loss 1 [expr {[dict get $r recovery] ne {}}]
    check no_concurrent_orphans {} [dict get $r concurrent_statements]
    foreach family {concurrent_assertions concurrent_procedure_calls concurrent_signal_assignments process_headers sensitivity_lists} {
        check $family unrecognized [dict get $r capabilities $family]
    }
    concurrent_invariants $r $v
}
puts {Concurrent scoped coverage and recovery assertions passed}
