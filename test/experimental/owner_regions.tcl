# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set scratch $::env(AURIG_EXPERIMENTAL_SCRATCH)
file mkdir $scratch
proc check {label actual expected} {
    if {$actual ne $expected} {error [list $label expected $expected observed $actual]}
}
proc input {text {limits {}}} {
    set path [file join $::scratch owners.vhd.fixture]
    set fp [open $path w]
    puts $fp $text
    close $fp
    return [::vhdl_index::analyze_file $path 2008 $limits]
}
proc id {view role at} {::vhdl_index::regions::identity $view [list $role $at]}
proc status {view id cap} {
    set proof [::vhdl_index::regions::coverage $view $id $cap]
    return [dict get $proof completeness]
}
proc design_region {view name} {
    foreach u [dict get $view result units] {
        if {[dict get $u name] eq $name} {
            return [id $view region [lindex [dict get $u span] 0]]
        }
    }
    error [list missing_unit $name]
}

set r [input {package p is end; entity e is port (a : in bit); end; architecture a of e is begin end;}]
check sparse [dict get $r object_declarations] {}
set v [::vhdl_index::regions::view $r]
foreach name {p e a} {
    set key [design_region $v $name]
    set region [::vhdl_index::regions::region $v $key]
    check owner_available [dict get $region availability] proved
    check has_inventory_fence [llength [dict get $region inventory_span]] 2
    check empty_complete [status $v $key object_declarations] complete
}
check absent [status $v [id $v region 1] object_declarations] absent
set entity [design_region $v e]
set unit [id $v unit [lindex $entity 2]]
check separate_role [expr {$entity eq $unit}] 0
check interface [status $v $unit entity_interfaces] complete
check out_of_context [status $v $entity configuration_specifications] not_applicable

set r [input {package body p is
    function f return integer is
        variable x : integer;
        function g return integer is begin return 1; end;
    begin return g; end function wrong;
    procedure q is begin null; end;
end;
package s is end;}]
set v [::vhdl_index::regions::view $r]
set p [design_region $v p]
set s [design_region $v s]
check global_incomplete [dict get $r capabilities object_declarations] unrecognized
check safe_sibling [status $v $s object_declarations] complete
check outer_direct [status $v $p object_declarations] complete
check specs [status $v $p subprogram_specifications] complete
check unavailable_body [status $v $p subprogram_bodies] partial
set loss [lindex [dict get $r withdrawn_scopes] 0]
set f [lindex [dict get $loss span] 0]
check body_unavailable [status $v [id $v region $f] object_declarations] unavailable
check spec_usable [status $v [id $v specification $f] subprogram_specifications] complete
check withdrawn_parent [dict get [::vhdl_index::regions::region $v [id $v region $f]] parent_id] $p
set nested [lindex [dict get $loss contributors] 0]
check nested_kind [dict get $nested kind] withdrawn_region
set g [id $v region [lindex [dict get $nested span] 0]]
check nested_withdrawn [dict get [::vhdl_index::regions::region $v $g] availability] withdrawn
check nested_parent [dict get [::vhdl_index::regions::region $v $g] parent_id] [id $v region $f]
check nested_unavailable [status $v $g type_declarations] unavailable

set original $v
set r [input {package p is package nested is component c end component; end package; end;}]
set v [::vhdl_index::regions::view $r]
set p [design_region $v p]
check nested_summary [dict get $r capabilities component_declarations] recognized-but-unsupported
check direct_independent [status $v $p component_declarations] complete
set gap [lindex [dict get $r coverage_gaps] 0]
set g [id $v gap [lindex [dict get $gap span] 0]]
check gap_availability [dict get [::vhdl_index::regions::region $v $g] availability] unsupported
check gap_unavailable [status $v $g component_declarations] unavailable
check gap_parent [dict get [::vhdl_index::regions::region $v $g] parent_id] $p
check foreign_snapshot [catch {status $original $p component_declarations} msg options] 1
check identity_diagnostic [dict get $options -errorcode] {VHDL_INDEX REGION_ID}

set r [input {package p is group missing; group good is (signal); end;}]
set v [::vhdl_index::regions::view $r]
set p [design_region $v p]
check partial_templates [status $v $p group_templates] partial
check partial_groups [status $v $p group_declarations] partial
check unrelated_complete [status $v $p type_declarations] complete

set r [input {package p is end; package body p is procedure q is begin null; end; end;} {scopes 1}]
set v [::vhdl_index::regions::view $r]
set loss [lindex [dict get $r withdrawn_scopes] 0]
set err [id $v recovery [lindex [dict get $loss span] 0]]
check root_uncertain [dict get [::vhdl_index::regions::region $v $err] availability] uncertain
check root_unavailable [status $v $err object_declarations] unavailable
check prior_unit [status $v [design_region $v p] object_declarations] complete
puts "Owner regions passed on Tcl [info patchlevel]"
