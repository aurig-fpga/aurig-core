# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failures 0
proc check {label expected actual} {
    incr ::checks
    if {$expected ne $actual} {incr ::failures; puts [list FAIL $label expected $expected actual $actual]}
}
proc get {record key} {
    if {[dict exists $record $key]} {return [dict get $record $key]}
    return {}
}
proc fixture {label edition} {
    ::vhdl_index::analyze_file [file join $::tests fixtures $label.vhd.fixture] $edition
}
proc inline {label text {limits {}}} {
    file mkdir $::env(AURIG_EXPERIMENTAL_SCRATCH)
    set path [file join $::env(AURIG_EXPERIMENTAL_SCRATCH) $label.vhd.fixture]
    set handle [open $path w]
    puts $handle $text
    close $handle
    ::vhdl_index::analyze_file $path 2008 $limits
}
proc cap {r name} {get [dict get $r capabilities] $name}
proc rows {r} {
    set result {}
    foreach scope [dict get $r object_declarations] {lappend result {*}[get $scope declarations]}
    return $result
}
proc gap_kinds {row} {
    set kinds {}
    foreach gap [get $row contributors] {lappend kinds [dict get $gap kind]}
    return [lsort -unique $kinds]
}
proc surface {r extent} {::vhdl_index::slice [dict get $r snapshot] $extent}
proc verify_source {r} {
    set text {}
    set offset 0
    foreach entry [dict get $r ledger] {
        lassign $entry _ start end
        if {$start != $offset} {error "ledger hole at $offset"}
        append text [surface $r [list $start $end]]
        set offset $end
    }
    check reconstructed [dict get $r snapshot text] $text
}

set control [fixture composition-control 2008]
check control-component recognized-but-unsupported [cap $control component_declarations]
set failed [fixture composition-withdrawn 2008]
check mismatch MISMATCHED_END_NAME [dict get [lindex [dict get $failed structural_diagnostics] 0] code]
check withdrawn-nested-component unrecognized [cap $failed component_declarations]
check component-records-absent {} [rows $failed]
check unrelated-interface parsed [cap $failed entity_interfaces]
set lost [lindex [dict get $failed withdrawn_scopes] 0]
check inherited-gap package [gap_kinds $lost]
verify_source $failed

foreach edition {1993 2002 2008} {
    set r [fixture configuration-owner $edition]
    set owner {}
    foreach scope [dict get $r object_declarations] {
        if {[dict get $scope kind] eq "configuration"} {set owner $scope}
    }
    check "$edition config owner" 1 [expr {$owner ne {}}]
    if {$owner eq {}} {continue}
    set config [lindex [dict get $r units] end]
    check config-identity [lindex [dict get $config span] 0] [dict get $owner id]
    check configuration-name cfg [surface $r [dict get $owner name_span]]
    set kinds {}
    foreach row [dict get $owner declarations] {
        check owned [dict get $owner id] [dict get $row owner_id]
        lappend kinds [dict get $row kind]
    }
    check owned-rows {local_use attribute_specification} $kinds
    check outer-use-context 1 [llength [dict get $config context]]
    check config-declarations-end for [string range [dict get $r snapshot text] \
        [lindex [dict get $owner declarative_span] 1] [expr {[lindex [dict get $owner declarative_span] 1] + 2}]]
    check opaque-block recognized-but-unsupported [cap $r configuration_blocks]
    check opaque-block-use recognized-but-unsupported [cap $r local_use_clauses]
    check unrelated-objects parsed [cap $r object_declarations]
    verify_source $r
}

set r [inline nested-loss {package body p is
    procedure q is
        type t is protected body
            package nested is component c end component; end package;
        end protected body wrong_t;
    begin null; end procedure wrong_q;
end package body wrong_p;
package sibling is constant survived : bit := '1'; end;}]
check multi-level-mask unrecognized [cap $r component_declarations]
check one-outer-withdrawal 1 [llength [dict get $r withdrawn_scopes]]
set lost [lindex [dict get $r withdrawn_scopes] 0]
check multi-level-provenance {package procedure protected_body} [gap_kinds $lost]
set scopes [dict get $r object_declarations]
set recent [lindex $scopes end]
check safe-sibling sibling [surface $r [dict get $recent name_span]]
check nested-declarations-withdrawn {} [rows $r]
verify_source $r

set r [inline blocks {entity e is end; architecture rtl of e is begin
  b: block is component cb end component; begin end block;
  g: if true generate component cg end component; begin end generate;
end architecture wrong;}]
check block-and-generate {block generate} [gap_kinds [lindex [dict get $r withdrawn_scopes] 0]]
check blocked-components unrecognized [cap $r component_declarations]
check scope-limit [list configuration_blocks unrecognized] \
    [list configuration_blocks [cap [inline limits {entity e is end; configuration c of e is for rtl end for; end;} {scopes 1}] configuration_blocks]]
check delimiter-limit [list component_declarations unrecognized] \
    [list component_declarations [cap [inline limits-delim {package p is component c generic (x : bit := ('0')); end component; end;} {delimiters 1}] component_declarations]]
puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
