# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failures 0
proc check {label expected actual} {
    incr ::checks
    if {$expected ne $actual} {incr ::failures; puts [list FAIL $label expected $expected actual $actual]}
}
proc read_fixture {stub edition} {
    set ::r [::vhdl_index::analyze_file [file join $::tests fixtures $stub.vhd.fixture] $edition]
    set ::rows {}
    foreach scope [dict get $::r object_declarations] {
        if {![dict exists $scope declarations]} {continue}
        foreach row [dict get $scope declarations] {
            set kind [dict get $row kind]
            if {$kind ni {disconnect local_use configuration_specification}} {continue}
            check owner [dict get $scope id] [dict get $row owner_id]
            dict lappend ::rows $kind $row
        }
    }
}
proc text {row key} {
    if {![dict exists $row $key] || [dict get $row $key] eq {}} {return {}}
    ::vhdl_index::slice [dict get $::r snapshot] [dict get $row $key]
}
proc capability {name} {dict get $::r capabilities $name}
proc codes {rows} {
    set result {}
    foreach row $rows {
        foreach issue [dict get $row diagnostics] {lappend result [dict get $issue code]}
    }
    return $result
}
foreach edition {1993 2002 2008} {
    read_fixture specifications $edition
    foreach cap {disconnect_specifications local_use_clauses configuration_specifications} {
        check "$edition $cap" parsed [capability $cap]
    }
    check nested-config-block recognized-but-unsupported [capability configuration_blocks]
    set use [lindex [dict get $rows local_use] 0]
    check no-flattened-binding-use 1 [llength [dict get $rows local_use]]
    check use-surface {use work.annotations.k, work.annotations.all;} [text $use span]
    lassign [dict get $use names] selected imported
    check use-component-count 3 [llength [dict get $selected components]]
    check use-wildcard work.annotations.all [text $imported span]
    set entity [lindex [dict get $r units] 4]
    check separate-context 1 [llength [dict get $entity context]]
    set disconnect [lindex [dict get $rows disconnect] 0]
    check guarded-signal-spec {s, t : bit} [text $disconnect guarded_signal_span]
    check time-expression {(1 + 2) * 1 ns} [text $disconnect time_span]
    check after-keyword after [text $disconnect after_span]
    lassign [dict get $rows configuration_specification] named other all
    check specification-count 3 [llength [dict get $rows configuration_specification]]
    check label-sequence {first, second} [text $named selector_span]
    check label-count 2 [llength [dict get $named selected_names]]
    set bound [dict get $named binding]
    check exact-entity-aspect {entity work.child(behavior)} [text $bound aspect_span]
    check separate-use use [text $bound use_span]
    check architecture-designator behavior [text $bound architecture_name_span]
    check generic-map {generic map (g => k)} [text [dict get $bound generic_map] span]
    check port-map {port map (p => '0')} [text [dict get $bound port_map] span]
    check others-selector others [dict get $other selector_kind]
    check configuration-target work.child_configuration [text [dict get $other binding] target_span]
    check all-selector all [dict get $all selector_kind]
    check open-aspect open [text [dict get $all binding] aspect_span]
    check opaque-expressions opaque [capability expressions]
}
foreach edition {1993 2002 2008} {
    read_fixture specifications-modern $edition
    set modern [lindex [dict get $rows configuration_specification] 0]
    check explicit-terminator {end for;} [text $modern end_for_span]
    check binding-separator {;} [text $modern binding_terminator_span]
    set expected [expr {$edition == 2008 ? "parsed" : "recognized-but-unsupported"}]
    check "$edition explicit-end coverage" $expected [capability configuration_specifications]
}
read_fixture specifications-recovery 2008
set disconnections [dict get $rows disconnect]
check disconnect-recovery {DISCONNECT_MISSING_SEMICOLON DISCONNECT_EMPTY_PAYLOAD} [codes $disconnections]
check selected-guarded-name {a.data(0)} [text [lindex [dict get [lindex $disconnections end] selected_names] 0] span]
check selected-type std.standard.bit [text [lindex $disconnections end] type_mark_span]
check local-use-recovered parsed [dict get [lindex [dict get $rows local_use] 0] status]
set configs [dict get $rows configuration_specification]
check diagnosed-configs {CONFIGURATION_SPECIFICATION_EXPECTED_NAME CONFIGURATION_SPECIFICATION_EXPECTED_ARCHITECTURE_CLOSE CONFIGURATION_SPECIFICATION_EMPTY_GROUP UNSUPPORTED_VERIFICATION_UNIT_BINDING CONFIGURATION_SPECIFICATION_MISSING_END_SEPARATOR} [codes $configs]
check compound-unavailable recognized-but-unsupported [dict get [lindex $configs 3] status]
check vunit-bounded 1 [llength [dict get [lindex $configs 3] verification_unit_binding_spans]]
check proved-sibling 1 [llength [dict get [lindex [dict get $r object_declarations] 0] entries]]
puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
