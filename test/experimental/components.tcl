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
    set ::rows {}
    foreach scope [dict get $::r object_declarations] {
        if {![dict exists $scope declarations]} {continue}
        foreach row [dict get $scope declarations] {
            if {[dict get $row kind] ne "component"} {continue}
            check ownership [dict get $scope id] [dict get $row owner_id]
            lappend ::rows $row
        }
    }
}
proc text {row key} {
    set extent [dict get $row $key]
    if {$extent eq {}} {return {}}
    ::vhdl_index::slice [dict get $::r snapshot] $extent
}
proc codes {row} {
    set codes {}
    foreach issue [dict get $row diagnostics] {lappend codes [dict get $issue code]}
    return $codes
}
foreach edition {1993 2002 2008} {
    read_fixture components $edition
    check "$edition coverage" parsed [dict get $r capabilities component_declarations]
    check component-count 3 [llength $rows]
    lassign $rows small grouped empty
    check optional-is {} [dict get $small is_span]
    check closing-spelling SMALL [text $small end_name_span]
    check exact-close {end component SMALL;} [text $small component_terminator_span]
    check explicit-is is [text $grouped is_span]
    lassign [dict get $grouped clauses] generic port
    check generic-name-count 2 [llength [dict get [lindex [dict get $generic items] 0] names]]
    check port-count 2 [llength [dict get $port items]]
    check port-subtype {bit_vector(size - 1 downto 0)} [text [lindex [dict get $port items] 0] subtype_span]
    check empty-clauses {} [dict get $empty clauses]
    check separate-entity-count 1 [llength [dict get $r entity_interfaces]]
    check entity-clause-count 2 [llength [dict get [lindex [dict get $r entity_interfaces] 0] clauses]]
    set architecture [lindex [dict get $r object_declarations] 0]
    check old-scope-count 2 [llength [dict get $r object_declarations]]
    check ordinary-object-count 1 [llength [dict get $architecture entries]]
}
read_fixture components-recovery 2008
check component-recovery-count 4 [llength $rows]
lassign $rows reversed wrong missing good
check reversed-errors {INTERFACE_MISSING_CLAUSE_SEMICOLON INTERFACE_INVALID_CLAUSE_ORDER INTERFACE_INVALID_CLAUSE_ORDER} [codes $reversed]
check mismatched-unproved unrecognized [dict get $wrong status]
check mismatched-withdrawn-clauses {} [dict get $wrong clauses]
check mismatched-provenance COMPONENT_UNPROVEN_SCOPE [codes $wrong]
check unaffected-objects parsed [dict get $r capabilities object_declarations]
check missing-terminator COMPONENT_MISSING_SEMICOLON [codes $missing]
check recovered-component parsed [dict get $good status]
check recovered-object 1 [llength [dict get [lindex [dict get $r object_declarations] 0] entries]]
read_fixture components-unsafe 2008
check unsafe-component-cause UNPROVEN_COMPONENT_END [dict get [lindex [dict get $r structural_diagnostics] 0] code]
check prior-unit-only 1 [llength [dict get $r units]]
check prior-component-only 1 [llength $rows]
check unsafe-coverage unrecognized [dict get $r capabilities component_declarations]
puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
