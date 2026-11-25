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
proc read_types {name edition} {
    set ::result [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
    set ::types {}
    set ::objects {}
    foreach scope [dict get $::result object_declarations] {
        foreach item [dict get $scope types] {
            check owner [dict get $scope id] [dict get $item owner_id]
            dict set ::types [text $item name_span] [list [dict get $scope kind] $item]
        }
        foreach entry [dict get $scope entries] {
            for {set i 0} {$i < [lindex $entry 1]} {incr i} {
                set object [::vhdl_index::object::record $::result $scope $entry $i]
                lappend ::objects [::vhdl_index::slice [dict get $::result snapshot] [lindex [dict get $object names] 0]]
            }
        }
    }
}
proc item {name} {return [lindex [dict get $::types $name] 1]}
proc code {entry} {return [dict get [lindex [dict get $entry diagnostics] 0] code]}
proc finish {} {
    puts [list Tcl [info patchlevel] assertions $::assertions failures $::failures]
    exit [expr {$::failures != 0}]
}

set extended [format {%cFile, element;%c} 92 92]
foreach edition {1993 2002 2008} {
    read_types access-file-types $edition
    check "$edition access" parsed [dict get [item handle] status]
    check "$edition file" parsed [dict get [item data_file_t] status]
    if {![dict exists [item handle] designated_subtype_span]} {continue}
    check type-status parsed [dict get $result capabilities type_declarations]
    check type-diagnostics {} [dict get $result type_diagnostics]
    foreach {name scope kind mark} [list handle package access node_t lanes package access std.standard.bit_vector \
                                   data_file_t package file $extended integer_file_t package file std.standard.integer \
                                   body_reference package_body access std.standard.integer procedure_file procedure file integer \
                                   entity_file entity file bit architecture_reference architecture access bit \
                                   process_file process file bit] {
        set type [item $name]
        check declaration-kind $kind [dict get $type kind]
        check scope-kind $scope [lindex [dict get $types $name] 0]
        check exact-type-mark $mark [text $type type_mark_span]
        check exact-type-keyword $kind [text $type ${kind}_keyword_span]
        check terminator {;} [text $type terminator_span]
        if {$kind eq "file"} {
            check type-connector of [text $type of_span]
            check definition "file of $mark" [text $type definition_span]
        }
    }
    set type [item lanes]
    check designated {std.standard.bit_vector(7 downto 0)} [text $type designated_subtype_span]
    check constraint {(7 downto 0)} [text $type constraint_span]
    set type [item resolved_reference]
    check resolver-span choose [text $type resolution_span]
    check resolver-kind scalar [dict get $type resolution_kind]
    check resolved-type-mark bit [text $type type_mark_span]
    check access-object-and-file-opaque {pointer} $objects
}
if {![dict exists [item handle] designated_subtype_span]} {finish}

read_types access-file-2008 2008
check nested-constraint {(open)(7 downto 0)} [text [item nested_reference] constraint_span]
check access-subtype-attribute {exemplar'subtype} [text [item attribute_reference] type_mark_span]
check access-subtype-attribute-status parsed [dict get [item attribute_reference] status]
check named-file-mark file_element [text [item attribute_file] type_mark_span]
check named-file-mark-status parsed [dict get [item attribute_file] status]
read_types access-file-attribute 2008
check direct-file-mark {exemplar'subtype} [text [item attribute_file] type_mark_span]
check direct-file-mark-status parsed [dict get [item attribute_file] status]
foreach edition {1993 2002} {
    read_types access-file-2008 $edition
    foreach name {nested_reference attribute_reference file_element} {
        check "$edition $name" recognized-but-unsupported [dict get [item $name] status]
    }
    read_types access-file-attribute $edition
    check "$edition file type mark" recognized-but-unsupported [dict get [item attribute_file] status]
}

read_types access-file-recovery 2008
foreach {name expected} {
    no_subtype TYPE_EXPECTED_NAME bad_constraint TYPE_EMPTY_PAYLOAD
    no_of TYPE_EXPECTED_FILE_OF no_mark TYPE_EXPECTED_NAME file_range TYPE_UNEXPECTED_TAIL
    file_constraint TYPE_UNEXPECTED_TAIL file_resolution TYPE_UNEXPECTED_TAIL
    missing_tail TYPE_MISSING_SEMICOLON
} {
    check "$name malformed" malformed [dict get [item $name] status]
    check "$name diagnosis" $expected [code [item $name]]
}
foreach name {obscures_object obscures_type} {
    check "$name unrecognized" unrecognized [dict get [item $name] status]
    check "$name unsafe cause" OBJECT_OPAQUE_BOUNDARY [dict get [lindex [dict get [item $name] diagnostics] 0] cause]
}
foreach name {recovered_access recovered_file saved} {
    check "$name parsed" parsed [dict get [item $name] status]
}
check withheld-type 0 [dict exists $types withheld_type]
check objects {clipped_access clipped_file visible_object} $objects
read_types access-file-unsafe 2008
check earlier-unit {existing} [dict keys $types]
check earlier-file parsed [dict get [item existing] status]
check structural-rollback unrecognized [dict get $result capabilities type_declarations]
check cause TYPE_UNPROVEN_SCOPE [code [dict create diagnostics [dict get $result type_diagnostics]]]

read_types opaque-expression-gap 2008
set type [item a]
check coordinator-expression-stays-opaque opaque [dict get $result capabilities expressions]
check coordinator-array-bounded parsed [dict get $type status]
check unvalidated-bound {3 natural} [text [lindex [dict get $type dimensions] 0] right_bound_span]
finish
