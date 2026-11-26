# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failed 0
proc check {label expected actual} {
    incr ::checks
    if {$actual ne $expected} {
        incr ::failed
        puts [list FAIL $label expected $expected actual $actual]
    }
}
proc surface {item key} {
    return [::vhdl_index::slice [dict get $::result snapshot] [dict get $item $key]]
}
proc analyze {name edition {limits {}}} {
    set ::result [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition $limits]
    set ::scopes {}
    set ::items {}
    foreach row [dict get $::result object_declarations] {
        dict set ::scopes [dict get $row id] $row
        if {[dict exists $row subprograms]} {
            foreach subprogram [dict get $row subprograms] {
                dict lappend ::items [surface $subprogram designator_span] $subprogram
            }
        }
    }
}
proc finish {} {
    puts [list Tcl [info patchlevel] assertions $::checks failures $::failed]
    exit [expr {$::failed != 0}]
}

foreach edition {1993 2002 2008} {
    analyze subprogram-bodies $edition
    check "$edition body capability" parsed [expr {[dict exists $result capabilities subprogram_bodies] ?
        [dict get $result capabilities subprogram_bodies] : "absent"}]
    if {![dict exists $result capabilities subprogram_bodies]} {continue}
    lassign [dict get $items value] prototype overload body bitBody
    check overload-count 4 [llength [dict get $items value]]
    check prototype-category declaration [dict get $prototype category]
    check prototype-no-scope 0 [dict exists $prototype body_scope_id]
    check overload-distinct 1 [expr {[dict get $prototype span] ne [dict get $overload span]}]
    check exact-is is [surface $body is_span]
    check exact-begin begin [surface $body begin_span]
    check body-tail {end function value;} [surface $body terminator_span]
    check bare-tail {end;} [surface $bitBody terminator_span]
    check named-tail {end store;} [surface [lindex [dict get $items store] 0] terminator_span]
    check operator-tail {end "+";} [surface [lindex [dict get $items {"+"}] 1] terminator_span]
    check typed-tail {end function;} [surface [lindex [dict get $items helper] 0] terminator_span]
    check sequential-opaque 1 [string match {*store(saved);*return v + saved;*} [surface $body sequential_span]]
    check no-local-in-sequential 0 [string match {*subtype index_t*} [surface $body sequential_span]]
    set bodyScope [dict get $scopes [dict get $body body_scope_id]]
    check formal-owner [dict get $body parameters] [dict get $bodyScope formal_parameters]
    check child-parent [dict get $body owner_id] [dict get $bodyScope parent_id]
    check local-variable-count 1 [llength [dict get $bodyScope entries]]
    check local-type index_t [surface [lindex [dict get $bodyScope types] 0] name_span]
    foreach {routine parent} {store function helper procedure constant_value entity outer architecture in_process process} {
        set child [lindex [dict get $items $routine] 0]
        check "$routine parent" $parent [dict get $scopes [dict get $child owner_id] kind]
        check "$routine unique scope" [lindex [dict get $child span] 0] [dict get $child body_scope_id]
    }
}
if {![dict exists $result capabilities subprogram_bodies]} {finish}
analyze subprogram-body-recovery 2008
check recovery-coverage unrecognized [dict get $result capabilities subprogram_bodies]
check retained-records {wrong_ending retained} [dict keys $items]
set wrong [lindex [dict get $items wrong_ending] 0]
check wrong-spec parsed [dict get $wrong status]
check wrong-body unrecognized [dict get $wrong body_status]
check withdrawn-scope 0 [dict exists $wrong body_scope_id]
check reason MISMATCHED_END_NAME [dict get [lindex [dict get $wrong body_diagnostics] 0] cause]
foreach scope [dict values $scopes] {
    if {[dict get $scope status] eq "unrecognized"} {
        check no-orphans {} [dict get $scope entries]
        check no-orphan-types {} [dict get $scope types]
        check no-orphan-subprograms 0 [dict exists $scope subprograms]
        check no-orphan-parameters 0 [dict exists $scope formal_parameters]
    }
}
check missing-begin MISSING_BEGIN [dict get [lindex [dict get $result structural_diagnostics] end] code]
check unowned-suffix 1 [expr {[dict get $result recovery] ne {}}]
analyze subprogram-bodies 2008 {scopes 2}
check scope-limit SCOPE_LIMIT [dict get [lindex [dict get $result structural_diagnostics] 0] code]
check remaining-scope-ids 1 [dict size $scopes]
check no-lost-overload 2 [llength [dict get $items value]]
finish
