# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failures 0
proc check {label expected actual} {
    incr ::checks
    if {$expected ne $actual} {incr ::failures; puts [list FAIL $label expected $expected actual $actual]}
}
proc surface {row key} {
    if {![dict exists $row $key] || [dict get $row $key] eq {}} {return {}}
    ::vhdl_index::slice [dict get $::r snapshot] [dict get $row $key]
}
proc read_fixture {name edition} {
    set ::r [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
    set ::rows {}
    foreach scope [dict get $::r object_declarations] {
        if {![dict exists $scope declarations]} {continue}
        foreach row [dict get $scope declarations] {
            check scope-owner [dict get $scope id] [dict get $row owner_id]
            lappend ::rows $row
        }
    }
}
proc capability {name} {dict get $::r capabilities $name}
proc diagnostic {row} {dict get [lindex [dict get $row diagnostics] 0] code}

foreach edition {1993 2002 2008} {
    read_fixture aliases-attributes $edition
    check "$edition alias coverage" parsed [capability alias_declarations]
    check "$edition attribute coverage" parsed [capability attribute_declarations]
    lassign $rows literal empty operator decl method func char pair all_decl all_spec other_decl other_spec sliced
    check "$edition declaration count" 13 [llength $rows]
    check char-designator character [dict get $literal designator_kind]
    check char-target flag_a [surface $literal aliased_name_span]
    check return-only-signature {[return flag]} [surface [dict get $literal signature] span]
    check extended-name {\renamed slice\ } "[surface $sliced name_span] "
    check selected-mark std.standard.bit_vector [surface $sliced type_mark_span]
    check constrained-alias {(0 to 1)} [surface $sliced constraint_span]
    check indexed-name {v(2 to 3)} [surface $sliced aliased_name_span]
    check empty-signature {[]} [surface [dict get $empty signature] span]
    check operator {"+"} [surface $operator name_span]
    set sig [dict get $operator signature]
    check signature-space {[integer, std.standard.integer return integer]} [surface $sig span]
    check return-connector return [surface $sig return_keyword_span]
    check commas 1 [llength [dict get $sig comma_spans]]
    check ordered-marks 2 [llength [dict get $sig type_mark_spans]]
    check attr-declaration attribute_declaration [dict get $decl kind]
    check declaration-type string [surface $decl type_mark_span]
    check attr-specification attribute_specification [dict get $method kind]
    check procedure-class procedure [surface $method entity_class_span]
    check entity-signature {[]} [surface [dict get [lindex [dict get $method entities] 0] signature] span]
    check punctuation {"alias; attribute"} [surface $method value_span]
    check designator-groups 2 [llength [dict get $pair entities]]
    check all-selector all [surface $all_spec selector_span]
    check attribute-reference {(v'length + 1)} [surface $all_spec value_span]
    check others-selector others [surface $other_spec selector_span]
    check terminator {;} [surface $other_spec terminator_span]
}
read_fixture aliases-attributes-modern 2008
lassign $rows external exposed private
check external-name {<< signal .name_host.s : bit >>} [surface $external aliased_name_span]
check external-status recognized-but-unsupported [dict get $external status]
check protected-attribute attribute_specification [dict get $exposed kind]
check protected-private-alias local_state [surface $private name_span]
check separate-owners 1 [expr {[dict get $exposed owner_id] != [dict get $private owner_id]}]
check general-expressions opaque [capability expressions]

read_fixture aliases-attributes-recovery 2008
check recovery-capability unrecognized [capability alias_declarations]
check uncertain-interval-may-hide-attributes unrecognized [capability attribute_declarations]
set ds {}
foreach item [lrange $rows 0 end-1] {
    if {[dict get $item status] ne "parsed"} {lappend ds [diagnostic $item]}
}
check bounded-reasons {ALIAS_EXPECTED_IS ALIAS_EXPECTED_NAME ALIAS_EXPECTED_NAME ALIAS_MISSING_SEMICOLON ATTRIBUTE_EXPECTED_ENTITY_CLASS_COLON ATTRIBUTE_EMPTY_PAYLOAD ALIAS_UNPROVEN_BOUNDARY} $ds
check recovered-alias retained [surface [lindex $rows end] name_span]
check recovered-alias-parsed parsed [dict get [lindex $rows end] status]
puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
