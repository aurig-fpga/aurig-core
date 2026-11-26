# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set count 0
set failures 0

proc check {label want actual} {
    incr ::count
    if {$want ne $actual} {
        incr ::failures
        puts [list FAIL $label expected $want actual $actual]
    }
}
proc surface {result extent} {
    if {$extent eq {}} {return {}}
    return [::vhdl_index::slice [dict get $result snapshot] $extent]
}
proc fixture {name edition} {
    return [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
}
proc inline {name text edition} {
    set path [file join $::env(AURIG_EXPERIMENTAL_SCRATCH) $name.vhd]
    file mkdir [file dirname $path]
    set out [open $path w]
    puts $out $text
    close $out
    return [::vhdl_index::analyze_file $path $edition]
}
proc encloses {outer inner} {
    if {$inner eq {}} {return 1}
    lassign $outer first last
    lassign $inner lo hi
    return [expr {$first <= $lo && $lo <= $hi && $hi <= $last}]
}
proc find_records {result} {
    set records {}
    set owners {}
    foreach scope [dict get $result object_declarations] {
        dict set owners [dict get $scope id] $scope
    }
    foreach scope [dict get $result object_declarations] {
        set kind [dict get $scope kind]
        set extent [dict get $scope span]
        set region [dict get $scope declarative_span]
        check "$kind region containment" 1 [encloses $extent $region]
        set parent [dict get $scope parent_id]
        if {$parent ne {}} {
            check "$kind parent containment" 1 [encloses [dict get $owners $parent span] $extent]
        }
        set previous [lindex $region 0]
        foreach entry [dict get $scope entries] {
            for {set index 0} {$index < [lindex $entry 1]} {incr index} {
                set record [::vhdl_index::object::record $result $scope $entry $index]
                set span [dict get $record span]
                check "$kind record containment" 1 [encloses $region $span]
                check "$kind owner identity" [dict get $scope id] [dict get $record owner_id]
                check "$kind declaration order" 1 [expr {$previous <= [lindex $span 0]}]
                set previous [lindex $span 1]
                dict for {key val} $record {
                    if {[string match *_span $key]} {
                        check "$kind $key contained" 1 [encloses $span $val]
                    }
                }
                set names {}
                set prev [lindex $span 0]
                foreach nameSpan [dict get $record names] {
                    check "$kind name contained" 1 [encloses $span $nameSpan]
                    check "$kind name order" 1 [expr {$prev <= [lindex $nameSpan 0]}]
                    set prev [lindex $nameSpan 1]
                    lappend names [surface $result $nameSpan]
                }
                set owner [surface $result [dict get $scope name_span]]
                lappend records [list $kind $owner $names $record]
            }
        }
    }
    return $records
}
proc signature {result} {
    set signature {}
    foreach row [find_records $result] {
        lassign $row scope owner names rec
        set fields {}
        foreach key {subtype_span constraint_span qualifier_span init_span terminator_span} {
            lappend fields [surface $result [dict get $rec $key]]
        }
        lappend signature [list $scope $owner [dict get $rec kind] $names {*}$fields \
            [dict get $rec status] [dict get $rec deferred]]
    }
    return $signature
}
proc diagnostic_codes {result} {
    set codes {}
    foreach diagnostic [dict get $result object_diagnostics] {
        lappend codes [dict get $diagnostic code]
    }
    return $codes
}

set r [fixture objects 2008]
check object-capability-present 1 [dict exists $r capabilities object_declarations]
if {$failures} {exit 1}
set expected {
    {package objects constant {deferred_a deferred_b} integer {} {} {} {;} parsed 1}
    {package objects constant semi character {} {} {';'} {;} parsed 0}
    {package objects constant message string {} {} {"end; variable := "} {;} parsed 0}
    {package objects constant quoted character {} {} {character'('"')} {;} parsed 0}
    {package objects shared_variable lock lock_type {} {} {} {;} parsed 0}
    {package_body objects constant deferred_a integer {} {} 1 {;} parsed 0}
    {package_body objects constant deferred_b integer {} {} 2 {;} parsed 0}
    {procedure touch variable protected_local integer {} {} 0 {;} parsed 0}
    {function computation variable {local_a local_b} std.standard.integer {} {} 0 {;} parsed 0}
    {procedure helper constant helper_only integer {} {} 3 {;} parsed 0}
    {entity object_test constant entity_only natural {} {} n {;} parsed 0}
    {architecture rtl signal {vector_a \\Vector\ B\\} {std.standard.bit_vector((2 + 1) downto 0)} {((2 + 1) downto 0)} {} {"0000"} {;} parsed 0}
    {architecture rtl signal bus_a std_logic {} bus {'0'} {;} parsed 0}
    {architecture rtl signal reg_a std_logic {} register {} {;} parsed 0}
    {architecture rtl signal room {integer range 0 to 63} {range 0 to 63} {} 10 {;} parsed 0}
    {process p variable {process_a process_b} integer {} {} {} {;} parsed 0}
    {process p constant process_only natural {} {} 2 {;} parsed 0}
}
set actual [signature $r]
check {scope and declaration count} [llength $expected] [llength $actual]
foreach want $expected got $actual {
    check "declaration [lindex $want 3]" [list {*}$want] $got
}
check {opaque nested ownership} recognized-but-unsupported [dict get $r capabilities object_declarations]
check {general declarations} opaque [dict get $r capabilities declarations]
check {expressions} opaque [dict get $r capabilities expressions]
check {interface capability} parsed [dict get $r capabilities entity_interfaces]

set r [fixture objects-2008 2008]
check 2008-coverage parsed [dict get $r capabilities object_declarations]
check 2008-composite [list \
    {package composite_objects signal resolved_vector {(resolved) std_ulogic_vector(7 downto 0)} {(7 downto 0)} {} {} {;} parsed 0} \
    {package composite_objects signal matrix {vector_array(0 to 1)(7 downto 0)} {(0 to 1)(7 downto 0)} {} {} {;} parsed 0} \
    {package composite_objects signal resolved_scalar {ieee.std_logic_1164.resolved std_ulogic} {} {} {} {;} parsed 0}] [signature $r]
foreach edition {1993 2002} {
    set r [fixture objects-2008 $edition]
    check "edition $edition coverage" recognized-but-unsupported [dict get $r capabilities object_declarations]
    check "edition $edition diagnostics" {EDITION_COMPOSITE_RESOLUTION EDITION_ELEMENT_CONSTRAINT} [diagnostic_codes $r]
}

set r [fixture objects-recovery 2008]
check safe-recovery malformed [dict get $r capabilities object_declarations]
check safe-recovery-diagnostics {OBJECT_EXPECTED_COLON OBJECT_EXPECTED_COLON OBJECT_EXPECTED_NAME OBJECT_EMPTY_PAYLOAD OBJECT_UNEXPECTED_TAIL OBJECT_MISSING_SEMICOLON MISSING_SEPARATOR OBJECT_INVALID_SIGNAL_KIND OBJECT_MISSING_SEMICOLON} [diagnostic_codes $r]
set records [find_records $r]
set saved [lindex $records 6]
check recovered-name saved [lindex $saved 2]
check recovered-status parsed [dict get [lindex $saved 3] status]
check recovered-terminator {;} [surface $r [dict get [lindex $saved 3] terminator_span]]
check recovered-unit after_recovery [dict get [lindex [dict get $r units] end] name]
check missing-terminator {} [dict get [lindex [lindex $records end] 3] terminator_span]

set r [fixture objects-unsafe 2008]
check unsafe-recovery unrecognized [dict get $r capabilities object_declarations]
check unsafe-only-prefix 1 [llength [find_records $r]]
set units {}
foreach unit [dict get $r units] {lappend units [dict get $unit name]}
check unsafe-no-speculative-owners {safe uncertain} $units
check unsafe-diagnostic OBJECT_UNPROVEN_SCOPE [lindex [diagnostic_codes $r] end]

foreach edition {1993 2002 2008} {
    set r [inline plain-shared {package p is shared variable v : integer; end;} $edition]
    check "$edition shared syntax" parsed [dict get $r capabilities object_declarations]
    check "$edition opaque type" shared_variable [dict get [lindex [lindex [find_records $r] 0] 3] kind]
    set r [inline scope-rules {entity e is variable illegal : integer; constant deferred : bit; end;
package p is end; package body p is signal illegal : bit; constant missing : bit; end;
architecture a of e is begin process is shared variable illegal : integer; begin wait; end process; end;} $edition]
    check "$edition scope rules" {OBJECT_CLASS_OUT_OF_SCOPE OBJECT_MISSING_INITIALIZATION OBJECT_CLASS_OUT_OF_SCOPE OBJECT_MISSING_INITIALIZATION OBJECT_CLASS_OUT_OF_SCOPE} [diagnostic_codes $r]
}

set r [inline empty {entity e is end; architecture rtl of e is begin end;} 2008]
check complete-absence parsed [dict get $r capabilities object_declarations]
check complete-absence-records {} [dict get $r object_declarations]
set r [inline truncated {package p is constant c : integer :=} 2008]
check truncated unrecognized [dict get $r capabilities object_declarations]
check truncated-records {} [dict get $r object_declarations]

set r [fixture objects-1993 1993]
check 1993-legal parsed [dict get $r capabilities object_declarations]
set expected {
    {package previous_edition shared_variable {old_a old_b} integer {} {} 1 {;} parsed 0}
    {package previous_edition signal limited {ieee.std_logic_1164.resolved std_ulogic range '0' to '1'} {range '0' to '1'} register {} {;} parsed 0}
    {package previous_edition signal resolution {ieee.std_logic_1164.resolved std_ulogic} {} {} '0' {;} parsed 0}
}
set actual [signature $r]
check older-name-count 3 [llength $actual]
foreach want $expected got $actual {
    check "1993 declaration [lindex $want 3]" [list {*}$want] $got
}
set group [lindex [find_records $r] 0 3]
check shared-class-span {shared variable} [surface $r [dict get $group class_span]]
check shared-span shared [surface $r [dict get $group shared_span]]
check shared-class-keyword-span variable [surface $r [dict get $group keyword_span]]
check init-marker-span := [surface $r [dict get $group init_marker_span]]

set r [inline nested-separator {package p is constant damaged : integer := to_integer(1; 2); constant saved : integer := 1; end;} 2008]
check nested-separator-diagnostic OBJECT_INVALID_GROUP_TOKEN [lindex [diagnostic_codes $r] 0]
lassign [find_records $r] damaged saved
check nested-separator-no-terminator {} [dict get [lindex $damaged 3] terminator_span]
check outer-separator-recovers saved [lindex $saved 2]

set r [inline missing-opaque-separator {package p is file stream : text constant hidden : integer := 1; end;} 2008]
check indexed-file-boundary-proved parsed [dict get $r capabilities object_declarations]
check indexed-file-still-owns-span file [lindex [dict get [lindex [dict get $r object_declarations] 0] opaque] 0 0]
check indexed-file-object-diagnostics {} [diagnostic_codes $r]
check indexed-file-keeps-sibling hidden [lindex [find_records $r] 0 2]
set file [lindex [dict get [lindex [dict get $r object_declarations] 0] declarations] 0]
check indexed-file-missing-separator FILE_OBJECT_MISSING_SEMICOLON [dict get [lindex [dict get $file diagnostics] 0] code]
set r [inline recovered-group-separator {package p is group selection : template (s) constant hidden : integer := 1; end;} 2008]
check indexed-group-boundary parsed [dict get $r capabilities object_declarations]
check indexed-group-keeps-sibling hidden [lindex [find_records $r] 0 2]
set group [lindex [dict get [lindex [dict get $r object_declarations] 0] declarations] 0]
check indexed-group-missing-separator GROUP_MISSING_SEMICOLON [dict get [lindex [dict get $group diagnostics] 0] code]
set r [inline missing-unsupported-opaque-separator {package p is property p1 is always true constant hidden : integer := 1; end;} 2008]
check unsupported-recovery-unavailable unrecognized [dict get $r capabilities object_declarations]
check unsupported-boundary-diagnostic OBJECT_OPAQUE_BOUNDARY [lindex [diagnostic_codes $r] 0]
check unsupported-recovery-no-speculation 0 [llength [find_records $r]]

set r [inline mismatched-label {entity e is end; architecture rtl of e is
    signal first : bit;
begin
    expected: process is variable withheld : bit; begin wait; end process actual;
    later: process is variable safe : bit; begin wait; end process later;
end;} 2008]
check mismatched-label-unavailable unrecognized [dict get $r capabilities object_declarations]
set names {}
foreach row [find_records $r] {lappend names [lindex $row 2]}
check mismatched-label-withholds-only-child {first safe} $names
check mismatched-label-structural-source MISMATCHED_END_NAME [dict get [lindex [dict get $r object_diagnostics] 0] cause]

foreach {name prefix} {
    type {type item is (one, two)}
    prototype {procedure entry}
    subtype {subtype item is integer}
} {
    set text "package p is $prefix constant obscured : integer := 1; end;"
    set r [inline "missing-$name-separator" $text 2008]
    check "$name recovery unavailable" unrecognized [dict get $r capabilities object_declarations]
    check "$name obscured object" OBJECT_OPAQUE_BOUNDARY [lindex [diagnostic_codes $r] 0]
    check "$name recovery no speculation" 0 [llength [find_records $r]]
}

puts [list Tcl [info patchlevel] assertions $count failures $failures]
exit [expr {$failures > 0}]
