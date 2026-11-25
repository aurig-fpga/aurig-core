# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set assertions 0
set failures 0
proc check {label expected actual} {
    incr ::assertions
    if {$expected ne $actual} {
        incr ::failures
        puts [list FAIL $label expected $expected actual $actual]
    }
}
proc text {entry key} {
    if {![dict exists $entry $key] || [dict get $entry $key] eq {}} {return {}}
    return [::vhdl_index::slice [dict get $::result snapshot] [dict get $entry $key]]
}
proc load_case {name edition} {
    set ::result [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
    set ::types {}
    set ::objects {}
    foreach scope [dict get $::result object_declarations] {
        foreach item [dict get $scope types] {
            check owner [dict get $scope id] [dict get $item owner_id]
            dict set ::types [text $item name_span] [list [dict get $scope kind] $item]
        }
        foreach entry [dict get $scope entries] {
            for {set index 0} {$index < [lindex $entry 1]} {incr index} {
                set row [::vhdl_index::object::record $::result $scope $entry $index]
                lappend ::objects [::vhdl_index::slice [dict get $::result snapshot] [lindex [dict get $row names] 0]]
            }
        }
    }
}
proc item {name} {return [lindex [dict get $::types $name] 1]}
proc issue {entry} {return [dict get [lindex [dict get $entry diagnostics] 0] code]}
proc finish {} {
    puts [list Tcl [info patchlevel] assertions $::assertions failures $::failures]
    exit [expr {$::failures != 0}]
}

set rate [format {%cRate, units;%c} 92 92]
set tick [format {%cTick; name%c} 92 92]
foreach edition {1993 2002 2008} {
    load_case physical-types $edition
    set type [item $rate]
    check "$edition physical" parsed [dict get $type status]
    if {![dict exists $type primary_unit]} {continue}
    check "$edition diagnostics" {} [dict get $result type_diagnostics]
    check range {range -1 to (7 + 4)} [text $type range_span]
    check range-keyword range [text $type range_keyword_span]
    check range-direction to [dict get $type direction]
    check range-left -1 [text $type left_bound_span]
    check range-right {(7 + 4)} [text $type right_bound_span]
    check units-keyword units [text $type units_keyword_span]
    check end-keyword end [text $type end_span]
    check end-units units [text $type end_units_span]
    check exact-closing-name $rate [text $type end_name_span]
    check physical-terminator "end units $rate;" [text $type physical_terminator_span]
    check declaration-semicolon {;} [text $type terminator_span]
    set primary [dict get $type primary_unit]
    check primary-name $tick [text $primary name_span]
    check primary-semicolon {;} [text $primary terminator_span]
    check primary-kind primary [dict get $primary kind]
    check primary-spelling "$tick;" [text $primary span]
    set rows [dict get $type secondary_units]
    check secondary-count 5 [llength $rows]
    set previous [lindex [dict get $primary span] 1]
    foreach row $rows name {scaled based decade implicit selected} magnitude {2 16#A# 1E1 {} 1} \
        reference [list $tick $tick $tick scaled physical_types.scaled] {
        check secondary-kind secondary [dict get $row kind]
        check declared-name $name [text $row name_span]
        check magnitude $magnitude [text $row magnitude_span]
        check reference $reference [text $row unit_reference_span]
        check assignment = [text $row assignment_span]
        check literal [string trim "$magnitude $reference"] [text $row literal_span]
        check unit-semicolon {;} [text $row terminator_span]
        check unit-source-order 1 [expr {[lindex [dict get $row span] 0] >= $previous}]
        set previous [lindex [dict get $row span] 1]
    }
    foreach row [linsert $rows 0 $primary] {
        check parent [lindex [dict get $type span] 0] [dict get $row type_id]
        check unit-status parsed [dict get $row status]
    }
    set type [item measured]
    check descending-direction downto [dict get $type direction]
    check basic-name-comparison MEASURED [text $type end_name_span]
    foreach {name kind} {elapsed_t package_body local_t procedure entity_t entity architecture_t architecture process_t process} {
        check type-owner-kind $kind [lindex [dict get $types $name] 0]
        check type-parsed parsed [dict get [item $name] status]
    }
    check no-unit-objects {sample} $objects
}
if {![dict exists [item $rate] primary_unit]} {finish}

foreach edition {1993 2002 2008} {
    load_case physical-range-attribute $edition
    set type [item measured]
    check range-attribute {sample'reverse_range(1)} [text $type range_attribute_span]
    check attribute-range-no-explicit-direction {} [dict get $type direction]
    check range-attribute-status parsed [dict get $type status]
}
load_case physical-recovery 2008
check physical-recovered parsed [dict get [item recovered] status]
check primary-separator TYPE_MISSING_UNIT_SEMICOLON [issue [dict get [item missing_primary_separator] primary_unit]]
check retained-unit next_unit [text [lindex [dict get [item missing_primary_separator] secondary_units] 0] name_span]
set rows [dict get [item malformed_members] secondary_units]
foreach row $rows expected {
    TYPE_EXPECTED_UNIT_ASSIGNMENT TYPE_EXPECTED_NAME TYPE_EXPECTED_NAME TYPE_EXPECTED_INTEGER_MAGNITUDE
    TYPE_EXPECTED_NAME TYPE_EXPECTED_NAME TYPE_MISSING_UNIT_SEMICOLON {} TYPE_MISSING_UNIT_SEMICOLON
} {
    set actual {}
    if {[dict get $row diagnostics] ne {}} {set actual [issue $row]}
    check member-diagnostic $expected $actual
}
check later-unit later_unit [text [lindex $rows 7] name_span]
check later-unit-status parsed [dict get [lindex $rows 7] status]
check empty-units TYPE_EXPECTED_PRIMARY_UNIT [issue [item empty_units]]
foreach name {bad_name obscured} {
    check "$name unrecognized" unrecognized [dict get [item $name] status]
    check "$name no unit claims" 0 [dict exists [item $name] primary_unit]
}
check mismatch-cause MISMATCHED_END_NAME [dict get [lindex [dict get [item bad_name] diagnostics] 0] cause]
check lost-coverage-cause OBJECT_OPAQUE_BOUNDARY [dict get [lindex [dict get [item obscured] diagnostics] 0] cause]
foreach name {no_tail_separator before_type} {
    check missing-type-semicolon TYPE_MISSING_SEMICOLON [issue [item $name]]
    check bounded-tail {end units} [text [item $name] physical_terminator_span]
}
check following-type parsed [dict get [item next_type] status]
check following-objects {clipped saved after_units} $objects

load_case physical-unsafe 2008
check earlier-unit {bounded} [dict keys $types]
check earlier-physical parsed [dict get [item bounded] status]
check unsafe-type unrecognized [dict get $result capabilities type_declarations]
check unsafe-object unrecognized [dict get $result capabilities object_declarations]
check unproved-unit-recovery TYPE_UNPROVEN_SCOPE [dict get [lindex [dict get $result type_diagnostics] 0] code]
finish
