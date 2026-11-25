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
proc field {r entry key} {
    if {[dict exists $entry $key] && [dict get $entry $key] ne {}} {
        return [::vhdl_index::slice [dict get $r snapshot] [dict get $entry $key]]
    }
    return {}
}
proc fixture {name edition} {
    return [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
}
proc collect_types {r} {
    set types {}
    foreach scope [dict get $r object_declarations] {
        foreach item [dict get $scope types] {
            check ownership [dict get $scope id] [dict get $item owner_id]
            dict set types [field $r $item name_span] [list [dict get $scope kind] $item]
        }
    }
    return $types
}
proc item {name} {
    return [lindex [dict get $::types $name] 1]
}
proc finish {} {
    puts [list Tcl [info patchlevel] assertions $::assertions failures $::failures]
    exit [expr {$::failures > 0}]
}

foreach edition {1993 2002 2008} {
    set r [fixture arrays $edition]
    set types [collect_types $r]
    check "$edition array status" parsed [dict get [item lane] status]
    if {![dict exists [item lane] dimensions]} {continue}
    check "$edition clean" {} [dict get $r type_diagnostics]
    check "$edition resolved envelopes" parsed [dict get $r capabilities type_declarations]
    foreach {name owner shape count} {
        lane package constrained 1
        explicit_index package constrained 1
        bitmap package unconstrained 1
        matrix package unconstrained 2
        vector_array package constrained 1
        package_body_array package_body constrained 1
        procedure_array procedure constrained 1
        entity_array entity constrained 1
        arch_array architecture constrained 1
        process_array process constrained 1
    } {
        check "$name scope" $owner [lindex [dict get $types $name] 0]
        check "$name shape" $shape [dict get [item $name] array_kind]
        check "$name dimensions" $count [llength [dict get [item $name] dimensions]]
        check "$name terminator" {;} [field $r [item $name] terminator_span]
    }
    set dimension [lindex [dict get [item lane] dimensions] 0]
    check subtype-index-kind subtype [dict get $dimension kind]
    check subtype-index-mark idx [field $r $dimension type_mark_span]
    set dimension [lindex [dict get [item explicit_index] dimensions] 0]
    check range-mark std.standard.natural [field $r $dimension type_mark_span]
    check range-keyword range [field $r $dimension range_keyword_span]
    check range-subtype {std.standard.natural range 0 to 3} [field $r $dimension span]
    set dimension [lindex [dict get [item matrix] dimensions] 0]
    check boxed-kind index_subtype [dict get $dimension kind]
    check boxed-mark std.standard.natural [field $r $dimension type_mark_span]
    check boxed-token <> [field $r $dimension box_span]
    set name [format {%cLanes, of;%c} 92 92]
    set array [item $name]
    lassign [dict get $array dimensions] subtype attribute explicit
    check attribute-kind range_attribute [dict get $attribute kind]
    check attribute-span {pattern'reverse_range(1)} [field $r $attribute range_attribute_span]
    check explicit-kind range [dict get $explicit kind]
    check direction downto [dict get $explicit direction]
    check left {(2 + 4)} [field $r $explicit left_bound_span]
    check right 3 [field $r $explicit right_bound_span]
    check array-keyword array [field $r $array array_keyword_span]
    check open {(} [field $r $array open_span]
    check close {)} [field $r $array close_span]
    check of of [field $r $array of_span]
    check separators 2 [llength [dict get $array separator_spans]]
    check element-mark std.standard.bit [field $r $array type_mark_span]
    check element-constraint {(7 downto 0)} [field $r [item vector_array] constraint_span]
    set dimension [lindex [dict get [item char_index] dimensions] 0]
    check lone-open-character {'('} [field $r $dimension left_bound_span]
}
if {![dict exists [item lane] dimensions]} {finish}

set r [fixture arrays-2008 2008]
set types [collect_types $r]
check modern-diagnostics {} [dict get $r type_diagnostics]
foreach {name constraint} {
    nested {(0 to 3)(7 downto 0)}
    outer_open {(open)(7 downto 0)}
    constrained_pair_array {(a(1 downto 0), b(2 downto 0))}
} {
    check "$name constraint" $constraint [field $r [item $name] constraint_span]
    check "$name parsed" parsed [dict get [item $name] status]
}
check indirect-indefinite-element bit_vector [field $r [item vector_array] type_mark_span]
check attribute-element {exemplar'subtype} [field $r [item attribute_element] type_mark_span]
foreach edition {1993 2002} {
    set r [fixture arrays-2008 $edition]
    set types [collect_types $r]
    foreach name {nested outer_open constrained_pair_array attribute_element} {
        check "$edition $name" recognized-but-unsupported [dict get [item $name] status]
    }
}

set r [fixture arrays-recovery 2008]
set types [collect_types $r]
foreach {name code} {
    missing_name TYPE_EXPECTED_INDEX
    missing_dimension TYPE_EXPECTED_INDEX
    empty_indexes TYPE_EXPECTED_INDEX
    mixed TYPE_MIXED_INDEX_CONSTRAINT
    missing_comma TYPE_EXPECTED_DIMENSION_SEPARATOR
    missing_bound TYPE_EMPTY_PAYLOAD
    boxed_bound TYPE_EMPTY_PAYLOAD
    missing_of TYPE_EXPECTED_ARRAY_OF
    missing_element TYPE_EXPECTED_NAME
    bad_element TYPE_EMPTY_PAYLOAD
    no_terminator TYPE_MISSING_SEMICOLON
} {
    check "$name malformed" malformed [dict get [item $name] status]
    check "$name diagnostic" $code [dict get [lindex [dict get [item $name] diagnostics] 0] code]
}
foreach name {recovered kept} {check "$name still indexed" parsed [dict get [item $name] status]}
foreach name {obscured obscures_next} {check "$name unproven" unrecognized [dict get [item $name] status]}
check buried-type-absent 0 [dict exists $types hidden_array]
set objects {}
set diagnostics {}
foreach scope [dict get $r object_declarations] {
    foreach entry [dict get $scope entries] {
        for {set i 0} {$i < [lindex $entry 1]} {incr i} {
            set object [::vhdl_index::object::record $r $scope $entry $i]
            lappend objects [::vhdl_index::slice [dict get $r snapshot] [lindex [dict get $object names] 0]]
        }
    }
}
foreach diagnostic [dict get $r object_diagnostics] {lappend diagnostics [dict get $diagnostic code]}
check object-members {clipped saved} $objects
check object-recovery {OBJECT_MISSING_SEMICOLON OBJECT_OPAQUE_BOUNDARY OBJECT_OPAQUE_BOUNDARY} $diagnostics
finish
