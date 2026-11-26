# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failures 0
proc check {label expected actual} {
    incr ::checks
    if {$expected ne $actual} {incr ::failures; puts [list FAIL $label expected $expected actual $actual]}
}
proc text {row key} {
    if {![dict exists $row $key]} {return {}}
    ::vhdl_index::slice [dict get $::r snapshot] [dict get $row $key]
}
proc name {row} {
    ::vhdl_index::slice [dict get $::r snapshot] [lindex [dict get $row names] 0]
}
proc read_fixture {fixture edition} {
    set ::r [::vhdl_index::analyze_file [file join $::tests fixtures $fixture.vhd.fixture] $edition]
    set ::files {}
    set ::owners {}
    foreach scope [dict get $::r object_declarations] {
        if {![dict exists $scope declarations]} {continue}
        foreach row [dict get $scope declarations] {
            if {[dict get $row kind] ne "file_object"} {continue}
            check owner [dict get $scope id] [dict get $row owner_id]
            lappend ::files $row
            lappend ::owners [dict get $scope kind]
        }
    }
}
foreach edition {1993 2002 2008} {
    read_fixture file-objects $edition
    check "$edition file coverage" parsed [dict get $r capabilities file_objects]
    check "$edition file groups" 4 [llength $files]
    lassign $files grouped lazy automatic local
    check scopes {package package package procedure} $owners
    check first-name f [name $grouped]
    set other [lindex [dict get $grouped names] 1]
    check second-name [format {%cother; file%c} 92 92] [::vhdl_index::slice [dict get $r snapshot] $other]
    check grouped-separators 1 [llength [dict get $grouped comma_spans]]
    check file-keyword file [text $grouped keyword_span]
    check open-keyword open [text $grouped open_span]
    check kind-expression read_mode [text $grouped open_kind_span]
    check is-keyword is [text $grouped is_span]
    check punctuation {"file; open is data"} [text $grouped logical_name_span]
    check no-open-info 0 [dict exists $lazy is_span]
    check selected-mark std.textio.text [text $lazy type_mark_span]
    check implicit-open-kind 0 [dict exists $automatic open_kind_span]
    check full-expression {"log." & "txt"} [text $automatic logical_name_span]
    check nested-expression {("nested")} [text $local logical_name_span]
    check local-terminator {;} [text $local terminator_span]
    set scope [lindex [dict get $r object_declarations] 0]
    check no-file-in-objects {} [dict get $scope entries]
    check independent-file-type file [dict get [lindex [dict get $scope types] 0] kind]
    set formal [lindex [dict get [lindex [dict get $scope subprograms] 0] parameters items] 0]
    check independent-formal-file file [dict get $formal effective_class]
}
foreach edition {2002 2008} {
    read_fixture file-objects-protected $edition
    check protected-file-scopes {package_body protected_body procedure} $owners
    check protected-file-count 3 [llength $files]
}
read_fixture file-objects-recovery 2008
set reasons {}
foreach row [lrange $files 0 end-1] {
    lappend reasons [dict get [lindex [dict get $row diagnostics] 0] code]
}
check failures {FILE_OBJECT_EMPTY_PAYLOAD FILE_OBJECT_EXPECTED_IS FILE_OBJECT_EMPTY_PAYLOAD FILE_OBJECT_LEGACY_FILE_MODE FILE_OBJECT_MISSING_SEMICOLON FILE_OBJECT_UNPROVEN_BOUNDARY} $reasons
check uncertain-file-coverage unrecognized [dict get $r capabilities file_objects]
check later-file retained [name [lindex $files end]]
check later-file-parsed parsed [dict get [lindex $files end] status]
check following-alias safe [text [lindex [dict get [lindex [dict get $r object_declarations] 0] declarations] 5] name_span]
puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
