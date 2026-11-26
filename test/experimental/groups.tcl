# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failures 0
proc check {label expected actual} {
    incr ::checks
    if {$expected ne $actual} {incr ::failures; puts [list FAIL $label expected $expected actual $actual]}
}
proc read_fixture {name edition} {
    set ::r [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
    set ::groups {}
    foreach scope [dict get $::r object_declarations] {
        if {![dict exists $scope declarations]} {continue}
        foreach row [dict get $scope declarations] {
            if {[dict get $row kind] ni {group group_template}} {continue}
            check group-owner [dict get $scope id] [dict get $row owner_id]
            lappend ::groups $row
        }
    }
}
proc text {row key} {
    if {![dict exists $row $key]} {return {}}
    ::vhdl_index::slice [dict get $::r snapshot] [dict get $row $key]
}
foreach edition {1993 2002 2008} {
    read_fixture groups $edition
    check "$edition templates" parsed [dict get $r capabilities group_templates]
    check "$edition group coverage" parsed [dict get $r capabilities group_declarations]
    check group-count 5 [llength $groups]
    lassign $groups tuple many pair repeated local
    set template [dict get $tuple members]
    check class-order {constant constant} [list [dict get [lindex $template 0] entity_class] [dict get [lindex $template 1] entity_class]]
    check exact-box <> [text [lindex [dict get $many members] 0] box_span]
    check selected-template work.holdings.many [text $repeated template_span]
    check extended [format {%cpair; group%c} 92 92] [text $pair name_span]
    check exact-constituent second [text [lindex [dict get $pair members] 1] span]
    check exact-open {(} [text $pair open_span]
    check exact-close {)} [text $pair close_span]
    check separator-count 1 [llength [dict get $pair comma_spans]]
    check terminator {;} [text $pair terminator_span]
    check config-own-group local [text $local name_span]
    check opaque-config-block recognized-but-unsupported [dict get $r capabilities configuration_blocks]
}
read_fixture groups-character 2008
set character [lindex [dict get [lindex $groups end] members] end]
check literal-constituent character [dict get $character kind]
check literal-spelling {'Q'} [text $character span]

read_fixture groups-recovery 2008
set reasons {}
foreach row [lrange $groups 0 end-1] {
    lappend reasons [dict get [lindex [dict get $row diagnostics] 0] code]
}
check malformed-reasons {GROUP_BOX_MUST_BE_LAST GROUP_EXPECTED_ENTITY_CLASS GROUP_EXPECTED_NAME GROUP_MISSING_SEMICOLON} $reasons
check recognized-sibling parsed [dict get [lindex $groups end] status]
check proved-object 1 [llength [dict get [lindex [dict get $r object_declarations] 0] entries]]
puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
