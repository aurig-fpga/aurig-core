# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]
set r [::vhdl_index::analyze_file [file join $tests fixtures shared-map-sites.vhd.fixture] 2008]
set v [::vhdl_index::regions::view $r]
set a [scope_find $v architecture {architecture rtl}]
set e [scope_find $v entity {entity top}]
set b [scope_find $v block b:]
proc map_actuals {r rows} {
    set uses {}
    foreach row $rows {lappend uses [surface $r [dict get $row actual_span]]}
    return $uses
}
check architecture {2 integer integer integer n q} [map_actuals $r [scope_rows $v $a map_associations]]
check entity {1 integer} [map_actuals $r [scope_rows $v $e map_associations]]
check block {7 s q} [map_actuals $r [scope_rows $v $b map_associations]]
set unit [lindex [::vhdl_index::query::units $v] 1]
set id [dict get $unit occurrence_id]
check library {1 integer} [map_actuals $r [scope_rows $v $id map_associations]]
set parsed [::vhdl_index::query::subtree $v $a map_associations]
check subtree {2 integer integer integer n q 7 s q} [map_actuals $r [dict get $parsed rows]]
check completeness complete [dict get $parsed completeness]
set binding [dict get [lindex [scope_rows $v $a configuration_specifications] 0] binding generic_map]
check legacy_group {(n => n)} [surface $r [dict get $binding association_span]]
check bounded_contents {n => n} [surface $r [dict get $binding association_content_span]]
set clause [lindex [dict get [lindex [dict get $r entity_interfaces] 0] clauses] 0]
lassign [dict get $clause items] ordinary box default
check format associations [dict get $ordinary map_kind]
check box <> [dict get $box map_kind]
check default default [dict get $default map_kind]
check marker <> [surface $r [dict get $box generic_map special_span]]
check marker default [surface $r [dict get $default generic_map special_span]]
check special_rows {} [dict get $box generic_map associations]
scope_integrity $r $v
set mapped {component c generic (package p is new work.g generic map (1)); end component c;}
set malformed [string map {{end component c;} {end component wrong;}} $mapped]
set sibling {component d generic (package q is new work.g generic map (2)); end component d;}
foreach {case declarations expectedRows complete validation} [list \
    valid $mapped 1 complete parsed \
    withdrawn $malformed {} partial unrecognized \
    sibling_before "$sibling $malformed" 2 partial unrecognized \
    sibling_after "$malformed $sibling" 2 partial unrecognized \
    other_declaration "$malformed constant keep : integer := 7;" {} partial unrecognized] {
    set r [scope_input "entity e is end; architecture a of e is $declarations begin end;"]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    foreach method {direct subtree} {
        set out [::vhdl_index::query::$method $v $a map_associations]
        check "$case $method completeness" $complete [dict get $out completeness]
        check "$case $method rows" $expectedRows [map_actuals $r [dict get $out rows]]
        check "$case $method validation" $validation [dict get $out validation]
        set evidence [dict get $out evidence]
        check "$case $method evidence count" [expr {$complete eq "partial"}] [llength $evidence]
        foreach proof $evidence {
            check loss_owner $a [dict get $proof owner_id]
            check affected_component $malformed [surface $r [dict get $proof span]]
            set issue [lindex [dict get $proof diagnostics] 0]
            check loss_cause MISMATCHED_END_NAME [dict get $issue code]
            check loss_cause_span wrong [surface $r [dict get $issue span]]
        }
        foreach row [dict get $out rows] {check retained_owner $a [dict get $row owner_occurrence_id]}
    }
    check "$case file map coverage" $validation [dict get $r capabilities map_associations]
    check unrelated_instances complete [scope_complete $v $a instantiations]
    check component_inventory $complete [scope_complete $v $a component_declarations]
    if {$case eq "other_declaration"} {
        check unrelated_declaration 1 [llength [scope_rows $v $a object_declarations]]
    }
    scope_integrity $r $v
}

foreach {case edition declarations} [list \
    empty 2008 {} \
    no_clauses 2008 {component c end component wrong;} \
    ordinary_generics 2008 {component c generic (n : integer := 1); end component wrong;} \
    port_only 2008 {component c port (q : out bit); end component wrong;} \
    old_edition_93 1993 $malformed old_edition_02 2002 $malformed] {
    set r [scope_input "entity e is end; architecture a of e is $declarations begin end;" $edition]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    foreach method {direct subtree} {
        set out [::vhdl_index::query::$method $v $a map_associations]
        check "$case empty completeness" complete [dict get $out completeness]
        check "$case empty rows" {} [dict get $out rows]
        check "$case empty evidence" {} [dict get $out evidence]
    }
    check "$case empty file coverage" parsed [dict get $r capabilities map_associations]
    scope_integrity $r $v
}

set malformed_map {component c generic (package p is new work.g generic map (x => , y => 9)); end component c;}
set malformed_header {component c generic (package p is new work.g generic (1)); end component c;}
foreach {declarations expectedRows expectedValidation} [list \
    $malformed_map 9 malformed $malformed_header {} malformed \
    [string map {{end component c;} {end component wrong;}} $malformed_map] {} unrecognized \
    [string map {{end component c;} {end component wrong;}} $malformed_header] {} unrecognized] {
    set r [scope_input "entity e is end; architecture a of e is $declarations begin end;"]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    foreach method {direct subtree} {
        set out [::vhdl_index::query::$method $v $a map_associations]
        check malformed_map_coverage partial [dict get $out completeness]
        check malformed_map_validation $expectedValidation [dict get $out validation]
        check malformed_map_survivors $expectedRows [map_actuals $r [dict get $out rows]]
        check malformed_map_evidence 1 [llength [dict get $out evidence]]
    }
    check malformed_map_file $expectedValidation [dict get $r capabilities map_associations]
    scope_integrity $r $v
}

set r [scope_input "entity e is end; architecture a of e is
    package local_pack is $malformed end package local_pack;
    $sibling
begin end;"]
set v [::vhdl_index::regions::view $r]
set a [scope_find $v architecture {architecture a}]
set p [scope_find $v package {package local_pack}]
check nested_direct_owner partial [scope_complete $v $p map_associations]
check nested_architecture_direct complete [scope_complete $v $a map_associations]
set out [::vhdl_index::query::subtree $v $a map_associations]
check nested_architecture_subtree partial [dict get $out completeness]
check nested_sibling 2 [map_actuals $r [dict get $out rows]]
check nested_single_proof 1 [llength [dict get $out evidence]]
check nested_file unrecognized [dict get $r capabilities map_associations]
scope_integrity $r $v

foreach {declarations close keeper complete} [list \
    "package outer is $malformed end package wrong; $sibling" {end;} 2 partial \
    $malformed {end architecture wrong;} {} unavailable \
    "package outer is package inner is $malformed end package wrong_inner; end package wrong_outer;" \
        {end architecture wrong_arch;} {} unavailable] {
    set r [scope_input "entity e is end; architecture a of e is $declarations begin $close"]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set out [::vhdl_index::query::subtree $v $a map_associations]
    check enclosing_loss $complete [dict get $out completeness]
    check enclosing_survivors $keeper [map_actuals $r [dict get $out rows]]
    check enclosing_file unrecognized [dict get $r capabilities map_associations]
    set losses 0
    foreach loss [dict get $r withdrawn_scopes] {
        if {![dict exists $loss contributors]} {continue}
        foreach child [dict get $loss contributors] {
            if {[dict get $child kind] ne "component_interface_loss"} {continue}
            incr losses
            check composed_extent $malformed [surface $r [dict get $child span]]
            check composed_map_capability map_associations [dict get $child capabilities]
            set issue [lindex [dict get $child diagnostics] 0]
            check composed_original_cause MISMATCHED_END_NAME [dict get $issue code]
            check composed_related_span wrong [surface $r [dict get $issue span]]
        }
    }
    check one_composed_component_loss 1 $losses
    check live_maps $keeper [map_actuals $r [scope_rows $v $a map_associations]]
    scope_integrity $r $v
}

puts "Shared map consumer assertions passed"
