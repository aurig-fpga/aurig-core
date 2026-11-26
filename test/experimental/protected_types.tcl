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
proc analyze {name edition} {
    set ::result [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
    set ::scopes {}
    set ::types {}
    set ::subprograms {}
    foreach scope [dict get $::result object_declarations] {
        dict set ::scopes [dict get $scope id] $scope
        foreach item [dict get $scope types] {lappend ::types $item}
        if {[dict exists $scope subprograms]} {
            foreach item [dict get $scope subprograms] {lappend ::subprograms [surface $item designator_span]}
        }
    }
}
proc routines {scope} {
    set names {}
    foreach item [dict get $scope subprograms] {lappend names [surface $item designator_span]}
    return $names
}
proc finish {} {
    puts [list Tcl [info patchlevel] assertions $::checks failures $::failed]
    exit [expr {$::failed != 0}]
}

foreach edition {2002 2008} {
    analyze protected-types $edition
    check "$edition type coverage" parsed [dict get $result capabilities type_declarations]
    if {![dict exists [lindex $types 0] member_scope_id]} {continue}
    lassign $types declaration implementation sibling local
    set extended [format {%cgate; control%c} 92 92]
    check owner-name $extended [surface $declaration name_span]
    check declaration-kind protected [dict get $declaration kind]
    check body-kind protected_body [dict get $implementation kind]
    check declaration-terminator {end protected \gate; control\;} [surface $declaration protected_terminator_span]
    check body-terminator {end protected body \gate; control\;} [surface $implementation protected_terminator_span]
    check closing-name $extended [surface $declaration end_name_span]
    check keyword protected [surface $declaration protected_keyword_span]
    check body-keyword body [surface $implementation body_keyword_span]
    check member-span 1 [string match {*variable saved*} [surface $implementation member_span]]
    set exposed [dict get $scopes [dict get $declaration member_scope_id]]
    set private [dict get $scopes [dict get $implementation member_scope_id]]
    check declaration-parent [dict get $declaration owner_id] [dict get $exposed parent_id]
    check body-parent [dict get $implementation owner_id] [dict get $private parent_id]
    check distinct-occurrences 1 [expr {[dict get $exposed id] != [dict get $private id]}]
    check exposed-routines {set_value sample} [routines $exposed]
    check private-routines {reset_local reset_local set_value sample} [routines $private]
    check inherited-opaque-use use [lindex [lindex [dict get $exposed opaque] 0] 0]
    check opaque-attribute attribute [lindex [lindex [dict get $exposed opaque] 3] 0]
    check no-exposed-state 0 [llength [dict get $exposed entries]]
    check private-state 1 [llength [dict get $private entries]]
    check private-type stored_t [surface [lindex [dict get $private types] 0] name_span]
    set op [lindex [dict get $private subprograms] 2]
    set opScope [dict get $scopes [dict get $op body_scope_id]]
    check operation-owner [dict get $private id] [dict get $opScope parent_id]
    check nested-routine convert [routines $opScope]
    check opaque-sequential 1 [string match {*"end protected body; procedure"*} [surface $op sequential_span]]
    check outer-sibling next_type [surface $sibling name_span]
    check root-coverage {opaque opaque} [list [dict get $result capabilities declarations] [dict get $result capabilities sequential]]
}
if {![dict exists [lindex $types 0] member_scope_id]} {finish}
analyze protected-types 1993
check old-edition unrecognized [dict get $result capabilities type_declarations]
check old-edition-scopes {} $scopes
analyze protected-nested-opaque 2008
check nested-gap recognized-but-unsupported [dict get $result capabilities type_declarations]
set local [lindex $types 1]
set implementation [dict get $scopes [dict get $local member_scope_id]]
check nested-package-gap package [lindex [lindex [dict get $implementation gaps] 0] 0]
check no-nested-package-routine {run run} $subprograms
check no-nested-package-type 2 [llength $types]
analyze protected-nested-opaque 2002
check older-nested-package-rejected EDITION_NESTED_PACKAGE [dict get [lindex [dict get $result structural_diagnostics] 0] code]
analyze protected-recovery 2008
check incomplete-coverage unrecognized [dict get $result capabilities type_declarations]
lassign $types malformed uncertain
check malformed-members malformed [dict get $malformed status]
set exposed [dict get $scopes [dict get $malformed member_scope_id]]
check disallowed-object-not-claimed {} [dict get $exposed entries]
check disallowed-member-code TYPE_PROTECTED_MEMBER_OUT_OF_CONTEXT [dict get [lindex [dict get $malformed diagnostics] 0] code]
lassign [dict get $exposed subprograms] first second body
check recovered-method parsed [dict get $second status]
check missing-separator SUBPROGRAM_MISSING_SEMICOLON [dict get [lindex [dict get $first diagnostics] 0] code]
check no-out-of-context-body-scope 0 [dict exists $body body_scope_id]
check mismatched-status unrecognized [dict get $uncertain status]
check mismatched-no-scope 0 [dict exists $uncertain member_scope_id]
check mismatched-no-orphan 0 [dict exists $scopes [lindex [dict get $uncertain span] 0]]
check no-orphan-records {retained first second inappropriate retained_again} $subprograms
check unowned-suffix 1 [expr {[dict get $result recovery] ne {}}]
finish
