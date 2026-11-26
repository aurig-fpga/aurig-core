# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

proc instance_labels {rows} {
    set labels {}
    foreach row $rows {lappend labels [dict get $row label]}
    return $labels
}
proc span_surfaces {result spans} {
    set text {}
    foreach span $spans {lappend text [surface $result $span]}
    return $text
}
proc lmap_kind {rows} {
    set kinds {}
    foreach row $rows {lappend kinds [dict get $row category]}
    return $kinds
}
proc lmap_actual {rows} {
    set spans {}
    foreach row $rows {lappend spans [dict get $row actual_span]}
    return $spans
}
set r [::vhdl_index::analyze_file [file join $tests fixtures instantiation-statements.vhd.fixture] 2008]
set v [::vhdl_index::regions::view $r]
set a [scope_find $v architecture {architecture rtl}]
set e [scope_find $v entity {entity shell}]
set d [::vhdl_index::query::direct $v $a instantiations]
check direct partial [dict get $d completeness]
check categories {component component entity configuration} [lmap_kind [dict get $d rows]]
set direct [dict get $d rows]
lassign $direct explicit implicit named configured
set targets {}
foreach row $direct {
    lappend targets [surface $r [dict get $row target_span]]
    check owner $a [dict get $row owner_occurrence_id]
    check terminator {;} [surface $r [dict get $row terminator_span]]
    check colon : [surface $r [dict get $row colon_span]]
    check identity [list [dict get $r source_id] instantiation [lindex [dict get $row span] 0]] [dict get $row occurrence_id]
}
check targets [list repo.device device "lib.\\device.core\\" lib.startup] $targets
check explicit_keyword component [surface $r [dict get $explicit keyword_span]]
check implicit_keyword {} [dict get $implicit keyword_span]
check selector {(\RTL arch\)} [surface $r [dict get $named architecture_selector span]]
check selector_name "\\RTL arch\\" [surface $r [dict get $named architecture_selector name_span]]
check components [list lib "\\device.core\\"] [span_surfaces $r [dict get $named target_components]]
check open_actual open [dict get [lindex [dict get $implicit maps port associations] 0] actual_kind]
set proof [lindex [dict get $d evidence] 0]
check ambiguity {component_instantiation concurrent_procedure_call} [dict get $proof forms]
check ambiguity_extent {unknown: repo.step;} [surface $r [dict get $proof span]]
check candidates 1 [llength [dict get $d evidence]]
check entity_inapplicable not_applicable [scope_complete $v $e instantiations]
set b [scope_find $v block b:]
check block_empty complete [scope_complete $v $b instantiations]
check block_count 0 [llength [scope_rows $v $b instantiations]]
set u [::vhdl_index::query::subtree $v $a instantiations]
check subtree_partial partial [dict get $u completeness]
check subtree_order [list explicit implicit "\\named instance\\" configured nested first_instance second_instance third_instance zero_copy remaining_copy]     [instance_labels [dict get $u rows]]
foreach {kind prefix label} {
    for_generate f: nested
    generate_alternative {if first:} first_instance
    generate_alternative {elsif second:} second_instance
    generate_alternative {else third:} third_instance
    generate_alternative {when zero:} zero_copy
    generate_alternative {when remaining:} remaining_copy
} {
    set id [scope_find $v $kind $prefix]
    check instance_owner $id [dict get [lindex [scope_rows $v $id instantiations] 0] owner_occurrence_id]
    check direct_label $label [instance_labels [scope_rows $v $id instantiations]]
    check complete_local complete [scope_complete $v $id instantiations]
}
set associations [scope_rows $v $a map_associations]
check direct_associations {open 5 {calc((0 => 1, others => 2), 7)} open}     [span_surfaces $r [lmap_actual $associations]]
check association_inventory complete [scope_complete $v $a map_associations]
set p [scope_find $v process p:]
check sequential_inapplicable not_applicable [scope_complete $v $p instantiations]
scope_integrity $r $v

foreach edition {1993 2002 2008} {
    set r [scope_input {entity e is end; architecture a of e is begin
        k: entity lib.e(rtl);
        c: configuration lib.cfg;
        d: component comp;
        implicit: selected.comp port map (a, b => open);
    end;} $edition]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    check editions {entity configuration component component} [lmap_kind [scope_rows $v $a instantiations]]
    check complete complete [scope_complete $v $a instantiations]
    scope_integrity $r $v
}

foreach {body code} {
    {component c; keep: component q;} MISSING_INSTANTIATION_LABEL
    {c port map (a); keep: component q;} MISSING_INSTANTIATION_LABEL
    {u: entity ; keep: component q;} INSTANTIATION_EXPECTED_NAME
    {u: entity work..e; keep: component q;} INSTANTIATION_EXPECTED_NAME
    {u: entity work.e (rtl port map (a); keep: component q;} INSTANTIATION_EXPECTED_ARCHITECTURE_CLOSE
    {u: component c generic (a); keep: component q;} EXPECTED_TOKEN
    {u: component c generic map a; keep: component q;} ASSOCIATION_EXPECTED_ASSOCIATION_OPEN
    {u: component c generic map (a; keep: component q;} ASSOCIATION_EXPECTED_ASSOCIATION_CLOSE
    {u: component c generic map (a keep: component q;} ASSOCIATION_EXPECTED_ASSOCIATION_CLOSE
    {u: component c port map (a) generic map (1); keep: component q;} INSTANTIATION_MAP_ORDER
    {u: component c port map (a) port map (b); keep: component q;} INSTANTIATION_MAP_ORDER
    {u: component c keep: component q;} EXPECTED_INSTANTIATION_SEMICOLON
    {u: component c b: block begin end block; keep: component q;} EXPECTED_INSTANTIATION_SEMICOLON
    {u: component c p: process begin wait; end process; keep: component q;} EXPECTED_INSTANTIATION_SEMICOLON
    {u: component c process begin wait; end process; keep: component q;} EXPECTED_INSTANTIATION_SEMICOLON
    {u: component c generic map (f(a keep: component q;} ASSOCIATION_EXPECTED_ASSOCIATION_CLOSE
    {u: component c g: for i in 0 to 0 generate end generate; keep: component q;} EXPECTED_INSTANTIATION_SEMICOLON
} {
    set r [scope_input "entity e is end; architecture a of e is begin $body end;"]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set out [::vhdl_index::query::direct $v $a instantiations]
    check "$code completeness" partial [dict get $out completeness]
    check "$code survivor" keep [instance_labels [dict get $out rows]]
    check defect_code $code [dict get [lindex [dict get [lindex [dict get $out evidence] 0] diagnostics] 0] code]
    scope_integrity $r $v
}

set r [scope_input {entity e is end; architecture a of e is begin
    u: component c generic map (a => , b => 2,);
    g: if broken: true generate
        x: component c;
        amb: c;
        p: process begin wait; end process;
    end wrong;
    else generate
        y: component c;
    end generate;
end;}]
set v [::vhdl_index::regions::view $r]
set a [scope_find $v architecture {architecture a}]
check bounded_occurrence complete [scope_complete $v $a instantiations]
check bounded_map partial [scope_complete $v $a map_associations]
check good_association b [surface $r [dict get [lindex [scope_rows $v $a map_associations] 0] formal_span]]
set g [scope_find $v if_generate g:]
check scope_envelope not_applicable [scope_complete $v $g instantiations]
set gapped [scope_find $v generate_alternative {if broken:}]
check withdrawn unavailable [scope_complete $v $gapped instantiations]
set subtree [::vhdl_index::query::subtree $v $a instantiations]
check surviving_siblings {u y} [instance_labels [dict get $subtree rows]]
check subtree_withdrawal partial [dict get $subtree completeness]
check composed_candidates 1 [string match {*component_instantiation concurrent_procedure_call*} [dict get $subtree evidence]]
scope_integrity $r $v

foreach {source limits expected} {
    {entity e is end; architecture a of e is begin u: component} {} TRUNCATED_SCOPE
    {entity e is end; architecture a of e is begin p(0) u: component c; end;} {} UNPROVEN_CONCURRENT_BOUNDARY
    {entity e is end; architecture a of e is begin p(0) b: block begin end block; end;} {} UNPROVEN_CONCURRENT_BOUNDARY
    {entity e is end; architecture a of e is begin u: c port map (f(g(a))); end;} {delimiters 2} ASSOCIATION_DELIMITER_LIMIT
    {entity e is end; architecture a of e is begin u: component c; g: for i in 0 to 1 generate end generate; end;} {scopes 1} SCOPE_LIMIT
} {
    set r [scope_input $source 2008 $limits]
    set v [::vhdl_index::regions::view $r]
    check boundary $expected [scope_error $r]
    set loss [scope_find $v root {architecture a}]
    check unavailable_root unavailable [scope_complete $v $loss instantiations]
    check no_orphans {} [dict get $r instantiations]
    scope_integrity $r $v
}
puts "Instantiation ownership and recovery assertions passed"
