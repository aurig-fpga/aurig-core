# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failed 0

proc check {label expected actual} {
    incr ::checks
    if {$expected ne $actual} {
        incr ::failed
        puts [list FAIL $label expected $expected actual $actual]
    }
}
proc surface {item key} {
    if {![dict exists $item $key] || [dict get $item $key] eq {}} {return {}}
    return [::vhdl_index::slice [dict get $::result snapshot] [dict get $item $key]]
}
proc load_fixture {name edition} {
    set ::result [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
    set ::records {}
    foreach scope [dict get $::result object_declarations] {
        if {![dict exists $scope subprograms]} {continue}
        foreach row [dict get $scope subprograms] {
            check owner [dict get $scope id] [dict get $row owner_id]
            check snapshot [dict get $::result source_id] [dict get $row source_id]
            lappend ::records $row
        }
    }
}
proc named {name} {
    foreach row $::records {
        if {[surface $row designator_span] eq $name} {return $row}
    }
    error "missing subprogram $name"
}
proc code {item} {return [dict get [lindex [dict get $item diagnostics] 0] code]}
proc finish {} {
    puts [list Tcl [info patchlevel] assertions $::checks failures $::failed]
    exit [expr {$::failed != 0}]
}

foreach edition {1993 2002 2008} {
    load_fixture subprogram-specifications $edition
    check "$edition specification inventory" 6 [llength $records]
    if {$records eq {}} {continue}
    check capability parsed [dict get $result capabilities subprogram_specifications]
    set zero [named zero]
    check default-purity pure [dict get $zero effective_purity]
    check implicit-purity {} [dict get $zero explicit_purity]
    check return-mark std.standard.integer [surface $zero return_type_span]
    check exact-spec {function zero return std.standard.integer} [surface $zero specification_span]
    check procedure-no-return {} [surface [named ping] return_type_span]
    set operator [named {"+"}]
    check operator-designator operator [dict get $operator designator_kind]
    check operator-purity pure [surface $operator purity_span]
    check grouped-count 2 [llength [dict get [lindex [dict get $operator parameters items] 0] names]]
    set reader [named read_stream]
    check impure impure [dict get $reader effective_purity]
    check no-file-mode {} [dict get [lindex [dict get $reader parameters items] 0] effective_mode]
    set move [named move]
    lassign [dict get $move parameters items] first second third fourth
    check grouping 2 [llength [dict get $first names]]
    check default {(1 + 2)} [surface $first default_span]
    check implicit-class variable [dict get $second effective_class]
    check explicit-mode inout [dict get $third explicit_mode]
    check subtype {bit_vector(7 downto 0)} [surface $fourth subtype_span]
    set extended [named [format {%cwork; item%c} 92 92]]
    check opaque-default {"function; end; )"} [surface [lindex [dict get $extended parameters items] 0] default_span]
}
if {$records eq {}} {finish}

load_fixture subprogram-generics 2008
set ordinary [named identity]
check generic-item type [dict get [lindex [dict get $ordinary generic_parameters items] 0] category]
check parameter-keyword parameter [surface $ordinary parameter_keyword_span]
set instance [named identity_int]
check instantiation instantiation [dict get $instance category]
check instantiation-envelope recognized-but-unsupported [dict get $instance status]
check instance-target identity [surface $instance target_span]
check instance-map {generic map (integer)} [surface $instance generic_map_span]
foreach edition {1993 2002} {
    load_fixture subprogram-generics $edition
    check earlier-edition unrecognized [dict get $result capabilities subprogram_specifications]
}
load_fixture subprogram-spec-recovery 2008
foreach {name expected} {
    missing_return SUBPROGRAM_EXPECTED_RETURN
    bad SUBPROGRAM_EXPECTED_COLON
    bad_mode SUBPROGRAM_FUNCTION_PARAMETER
    separator_lost SUBPROGRAM_MISSING_SEMICOLON
    missing_parameter_list SUBPROGRAM_EXPECTED_OPEN
} {
    check malformed malformed [dict get [named $name] status]
    check reason $expected [code [named $name]]
}
check restored-sibling parsed [dict get [named retained] status]
check later-sibling parsed [dict get [named last_function] status]
finish
