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
puts "Shared map consumer assertions passed"
