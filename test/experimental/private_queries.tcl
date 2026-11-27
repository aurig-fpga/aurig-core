# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] owner_regions.tcl]
proc by_name {view id capability key} {
    set r [::vhdl_index::query::direct $view $id $capability]
    set names {}
    foreach row [dict get $r rows] {
        lappend names [::vhdl_index::query::text $view [dict get $view source_id] [dict get $row $key]]
    }
    return $names
}
set text {package p is
    group missing;
    group good is (signal);
    package nested is component c end component; end package;
    component visible generic (n, m : positive); end component;
    type pair is record x, y : bit; end record;
    type distance is range 0 to 3 units mm; cm = 10 mm; end units;
    function f (a, b : integer) return integer;
    function f (a : bit) return bit;
end;
entity e is end; architecture a of e is begin
    process is variable x : bit; begin null; end process;
end;}
set r [input $text]
set v [::vhdl_index::regions::view $r]
set p [design_region $v p]
set scopes [::vhdl_index::query::owners $v]
set roles {}
set last -1
foreach scope $scopes {
    lappend roles [lindex [dict get $scope id] 1]
    lassign [dict get $scope span] start end
    check ordered [expr {$start >= $last}] 1
    set last $start
    set parent [::vhdl_index::regions::region $v [dict get $scope parent_id]]
    check parent_present [dict get $parent availability] proved
    lassign [dict get $parent span] low high
    check containment [expr {$start >= $low && $end <= $high}] 1
}
check direct_complete [dict get [::vhdl_index::query::direct $v $p component_declarations] completeness] complete
set r [::vhdl_index::query::subtree $v $p component_declarations]
check subtree_complete [dict get $r completeness] complete
check subtree_visible_count [llength [dict get $r rows]] 2
check subtree_proof_count [llength [dict get $r evidence]] 0
check direct_groups [dict get [::vhdl_index::query::direct $v $p group_templates] completeness] partial
check group_records [llength [dict get [::vhdl_index::query::direct $v $p group_templates] rows]] 2
set proof [lindex [dict get [::vhdl_index::query::direct $v $p group_templates] evidence] 0]
check possible_families [dict get $proof capabilities] {group_templates group_declarations}
check possible_forms [dict get $proof forms] {group_template group}
check one_candidate_diagnostic [llength [dict get $proof diagnostics]] 1
check absent_rows [dict get [::vhdl_index::query::direct $v [id $v region 1] type_declarations] rows] {}
check complete_empty [dict get [::vhdl_index::query::direct $v [design_region $v e] type_declarations] completeness] complete
check overloads [by_name $v $p subprogram_specifications designator_span] {f f}
set specs [dict get [::vhdl_index::query::direct $v $p subprogram_specifications] rows]
set a [dict get [lindex $specs 0] occurrence_id]
set b [dict get [lindex $specs 1] occurrence_id]
check distinct_occurrences [expr {$a ne $b}] 1
set parameters [dict get [::vhdl_index::query::direct $v $a formal_parameters] rows]
check same_parameter_group [llength [dict get [lindex $parameters 0] names]] 2
check parameter_owner [dict get [lindex $parameters 0] owner_occurrence_id] $a
set arch [design_region $v a]
set rows [dict get [::vhdl_index::query::subtree $v $arch object_declarations] rows]
check process_visibility [llength $rows] 1
check no_promotion [llength [dict get [::vhdl_index::query::direct $v $arch object_declarations] rows]] 0

foreach scope $scopes {
    set key [dict get $scope id]
    switch -- [dict get $scope kind] {
        component {
            set clauses [dict get [::vhdl_index::query::direct $v $key component_interfaces] rows]
            if {[string match {component c *} [::vhdl_index::query::text $v [dict get $v source_id] [dict get $scope span]]]} {
                check nested_component_empty {} $clauses
                continue
            }
            set item [lindex $clauses 0]
            check component_names [llength [dict get [lindex [dict get $item items] 0] names]] 2
        }
        record {
            set item [lindex [dict get [::vhdl_index::query::direct $v $key record_fields] rows] 0]
            check record_names [llength [dict get $item names]] 2
        }
        physical {check physical_units [by_name $v $key physical_units name_span] {mm cm}}
    }
}
set snapshot [dict get $v source_id]
check slice [::vhdl_index::query::text $v $snapshot {0 7}] package
check pos [::vhdl_index::query::position $v $snapshot 0] {1 0}
foreach span {{-1 2} {4 2} {0 999999} {three 5} {0 5 9}} {
    check span_error [catch {::vhdl_index::query::text $v $snapshot $span}] 1
}
set newer [::vhdl_index::regions::view [input $text]]
check foreign_query [catch {::vhdl_index::query::direct $newer $p type_declarations}] 1
check foreign_span [catch {::vhdl_index::query::text $newer $snapshot {0 2}}] 1
puts "Private queries passed on Tcl [info patchlevel]"

source [file join $tests query_equivalence.tcl]
