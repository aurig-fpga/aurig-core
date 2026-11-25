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
proc surface {r span} {
    if {$span eq {}} {return {}}
    return [::vhdl_index::slice [dict get $r snapshot] $span]
}
proc field {r entry key} {
    if {[dict exists $entry $key]} {return [surface $r [dict get $entry $key]]}
    return {}
}
proc fixture {name edition} {
    return [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
}
proc collect_types {r} {
    set types {}
    foreach scope [dict get $r object_declarations] {
        foreach item [dict get $scope types] {
            check declaration-owner [dict get $scope id] [dict get $item owner_id]
            set name [field $r $item name_span]
            dict set types $name [list [dict get $scope kind] $item]
            if {[dict exists $item fields]} {
                set extent [dict get $item span]
                set end [lindex $extent 0]
                foreach member [dict get $item fields] {
                    lassign [dict get $member span] first last
                    check field-parent [lindex $extent 0] [dict get $member record_id]
                    check field-containment 1 [expr {$end <= $first && $first < $last && $last <= [lindex $extent 1]}]
                    set end $last
                }
            }
        }
    }
    return $types
}
proc item {name} {
    return [lindex [dict get $::types $name] 1]
}
proc issue {item} {
    return [dict get [lindex [dict get $item diagnostics] 0] code]
}
proc finish {} {
    puts [list Tcl [info patchlevel] assertions $::assertions failures $::failures]
    exit [expr {$::failures > 0}]
}

set packet [format {%cPacket, record;%c} 92 92]
set extended [format {%cRIGHT; FIELD%c} 92 92]
foreach edition {1993 2002 2008} {
    set r [fixture records $edition]
    set types [collect_types $r]
    check "$edition record status" parsed [dict get [item $packet] status]
    if {![dict exists [item $packet] fields]} {continue}
    check "$edition parsed" parsed [dict get $r capabilities type_declarations]
    check "$edition diagnostics" {} [dict get $r type_diagnostics]
    foreach {name owner count} [list $packet package 4 wrapped package 2 inside_body package_body 1 \
                               local_record function 1 entity_record entity 1 arch_record architecture 1 \
                               process_record process 1] {
        check "$name owner" $owner [lindex [dict get $types $name] 0]
        check "$name groups" $count [llength [dict get [item $name] fields]]
        check "$name record keyword" record [field $r [item $name] record_keyword_span]
        check "$name terminator" {;} [field $r [item $name] terminator_span]
    }
    lassign [dict get [item $packet] fields] pair content tag punct
    set names {}
    foreach name [dict get $pair names] {lappend names [surface $r $name]}
    check grouped-names [list left_field $extended] $names
    check grouped-separator , [surface $r [lindex [dict get $pair separator_spans] 0]]
    check grouped-colon : [field $r $pair colon_span]
    check grouped-terminator {;} [field $r $pair terminator_span]
    check selected-subtype std.standard.bit [field $r $pair type_mark_span]
    check array-field vector_a [field $r $content subtype_span]
    check nested-record $packet [field $r [lindex [dict get [item wrapped] fields] 0] type_mark_span]
    check constrained-surface {range -2 to 2} [field $r $tag constraint_span]
    check literal-punctuation {range '(' to ')'} [field $r $punct constraint_span]
    check closing-name $packet [field $r [item $packet] end_name_span]
    check record-tail "end record $packet;" [field $r [item $packet] record_terminator_span]
    check case-folded-close WRAPPED [field $r [item wrapped] end_name_span]
    check no-object-fields {} [dict get $r object_diagnostics]
    foreach scope [dict get $r object_declarations] {
        check no-ordinary-fields {} [dict get $scope entries]
        check no-members-as-scopes 0 [expr {[dict get $scope kind] eq "record"}]
    }
}
if {![dict exists [item $packet] fields]} {finish}

set r [fixture records-2008 2008]
set types [collect_types $r]
check indefinite-record parsed [dict get [item payload_t] status]
set fields [dict get [item payload_t] fields]
check indefinite-mark bit_vector [field $r [lindex $fields 0] type_mark_span]
check nested-constraints {(0 to 2)(3 downto 0)} [field $r [lindex $fields 1] constraint_span]
check nested-open {(open)(7 downto 0)} [field $r [lindex $fields 2] constraint_span]
check element-constraints {(data(1 downto 0), indefinite_storage(0 to 1))} \
    [field $r [lindex [dict get [item packet_t] fields] 0] constraint_span]
check subtype-attribute {exemplar'subtype} [field $r [lindex [dict get [item attribute_record] fields] 0] type_mark_span]
foreach edition {1993 2002} {
    set r [fixture records-2008 $edition]
    set types [collect_types $r]
    foreach name {payload_t packet_t attribute_record} {
        check "$edition $name" recognized-but-unsupported [dict get [item $name] status]
    }
}

set r [fixture records-recovery 2008]
set types [collect_types $r]
foreach {name code} {
    missing_separator TYPE_MISSING_FIELD_SEMICOLON
    missing_colon TYPE_EXPECTED_COLON
    missing_subtype TYPE_EXPECTED_NAME
    missing_bound TYPE_EMPTY_PAYLOAD
    empty_record TYPE_EXPECTED_RECORD_FIELD
    clips_before_object TYPE_MISSING_SEMICOLON
    clips_before_type TYPE_MISSING_SEMICOLON
} {
    check "$name status" malformed [dict get [item $name] status]
    check "$name diagnostic" $code [issue [item $name]]
}
foreach {name cause} {closing_mismatch MISMATCHED_END_NAME obscured OBJECT_OPAQUE_BOUNDARY} {
    check "$name uncertain" unrecognized [dict get [item $name] status]
    check "$name cause" $cause [dict get [lindex [dict get [item $name] diagnostics] 0] cause]
}
check field-sibling-status parsed [dict get [lindex [dict get [item missing_separator] fields] 1] status]
check field-sibling-names 2 [llength [dict get [lindex [dict get [item missing_separator] fields] 1] names]]
check field-recovery-after-bad-subtype parsed [dict get [lindex [dict get [item missing_bound] fields] 1] status]
check record-without-terminator {end record} [field $r [item clips_before_object] record_terminator_span]
check record-no-semicolon {} [field $r [item clips_before_type] terminator_span]
check hidden-type-absent 0 [dict exists $types hidden_type]
check saved-type parsed [dict get [item kept] status]
check recovered-type parsed [dict get [item recovered] status]
set objects {}
foreach scope [dict get $r object_declarations] {
    foreach entry [dict get $scope entries] {
        for {set i 0} {$i < [lindex $entry 1]} {incr i} {
            set object [::vhdl_index::object::record $r $scope $entry $i]
            lappend objects [surface $r [lindex [dict get $object names] 0]]
        }
    }
}
check recovered-objects {clipped recovered_object last_object} $objects

set r [fixture records-unsafe 2008]
set types [collect_types $r]
check retain-only-verified-unit {kept} [dict keys $types]
check unsafe-type-status unrecognized [dict get $r capabilities type_declarations]
check unsafe-object-status unrecognized [dict get $r capabilities object_declarations]
check unsafe-cause MISMATCHED_END_KIND [dict get [lindex [dict get $r type_diagnostics] 0] cause]
finish
