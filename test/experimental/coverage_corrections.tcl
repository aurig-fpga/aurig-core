# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failures 0
proc check {label expected actual} {
    incr ::checks
    if {$expected ne $actual} {
        incr ::failures
        puts [list FAIL $label expected $expected actual $actual]
    }
}
proc capability {r name} {dict get $r capabilities $name}
proc fixture {name {edition 2008}} {
    ::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition
}
proc inline {name text {edition 2008} {limits {}}} {
    set dest $::env(AURIG_EXPERIMENTAL_SCRATCH)
    file mkdir $dest
    set path [file join $dest $name.vhd.fixture]
    set out [open $path w]
    puts $out $text
    close $out
    ::vhdl_index::analyze_file $path $edition $limits
}
proc slice {r extent} {::vhdl_index::slice [dict get $r snapshot] $extent}
proc codes {r key} {
    set result {}
    foreach item [dict get $r $key] {lappend result [dict get $item code]}
    return $result
}
proc routines {r} {
    set names {}
    foreach scope [dict get $r object_declarations] {
        if {![dict exists $scope subprograms]} {continue}
        foreach item [dict get $scope subprograms] {lappend names [slice $r [dict get $item designator_span]]}
    }
    return $names
}
proc losses {r} {
    if {![dict exists $r withdrawn_scopes]} {return {}}
    dict get $r withdrawn_scopes
}
proc check_accounting {r} {
    set text {}
    set at 0
    foreach row [dict get $r ledger] {
        lassign $row _ start end
        if {$start != $at} {error "ledger hole at $at"}
        append text [slice $r [list $start $end]]
        set at $end
    }
    check reconstruction [dict get $r snapshot text] $text
}

set r [fixture coverage-withdrawal]
foreach name {object_declarations type_declarations subprogram_specifications subprogram_bodies} {
    check "withdrawn $name" unrecognized [capability $r $name]
}
check unrelated-interfaces parsed [capability $r entity_interfaces]
check local-gone-sibling-retained {f q} [routines $r]
check structural MISMATCHED_END_NAME [codes $r structural_diagnostics]
check object-provenance OBJECT_UNPROVEN_SCOPE [codes $r object_diagnostics]
check type-provenance TYPE_UNPROVEN_SCOPE [codes $r type_diagnostics]
set scope [lindex [dict get $r object_declarations] 0]
check only-valid-sibling-scope 2 [llength [dict get $r object_declarations]]
check empty-object-list {} [dict get $scope entries]
check empty-type-list {} [dict get $scope types]
set f [lindex [dict get $scope subprograms] 0]
check preserved-specification parsed [dict get $f status]
check failed-body unrecognized [dict get $f body_status]
check absent-body-link 0 [dict exists $f body_scope_id]
check withdrawal-count 1 [llength [losses $r]]
if {[llength [losses $r]]} {
    set loss [lindex [losses $r] 0]
    check exact-affected-extent [dict get $f span] [dict get $loss span]
    check wrong-source wrong [slice $r [dict get $loss diagnostic span]]
}
check_accounting $r

set r [inline nested-withdrawal {package body p is
type lock is protected body
  variable state : bit;
  procedure update is procedure inner is begin null; end; begin null; end procedure different;
end protected body wrong;
procedure retained is begin null; end;
end package body;}]
check enclosing-loss-supersedes-child 1 [llength [losses $r]]
check retained-routine retained [routines $r]
check withdrawn-protected-specs unrecognized [capability $r subprogram_specifications]
check withdrawn-protected-bodies unrecognized [capability $r subprogram_bodies]
check_accounting $r

set r [inline exposed-withdrawal {package p is
type lock is protected procedure update; end protected wrong;
end package;}]
check no-vacuous-subprogram-absence unrecognized [capability $r subprogram_specifications]
check exposed-has-no-bodies parsed [capability $r subprogram_bodies]
check exposed-has-no-objects parsed [capability $r object_declarations]
check no-orphan-records {} [routines $r]

set r [inline unit-withdrawal {entity e is generic (n : natural); procedure lost; end entity wrong;
entity next_e is generic (n : natural); end entity;}]
check bad-entity-interfaces unrecognized [capability $r entity_interfaces]
check only-other-entity 1 [llength [dict get $r entity_interfaces]]
check lost-prototype {} [routines $r]
check_accounting $r

foreach {name text limit reason} {
    unsafe {package body p is procedure q is begin null; end function;} {} EXPECTED_TOKEN
    scope {package body p is procedure q is begin null; end; end;} {scopes 1} SCOPE_LIMIT
    delimiter {entity e is constant x : integer := ((1)); end;} {delimiters 1} DELIMITER_LIMIT
    tokens {entity e is constant x : integer := ((1)); end;} {tokens 5} UNSUPPORTED_TOKEN
} {
    set r [inline $name $text 2008 $limit]
    check "$name root loss" 1 [llength [losses $r]]
    check "$name root cause" $reason [lindex [codes $r structural_diagnostics] 0]
    check "$name no scopes" {} [dict get $r object_declarations]
    check "$name no false absence" unrecognized [capability $r subprogram_specifications]
    check_accounting $r
}

set r [fixture operator-formal-invalid]
check invalid-formal-status malformed [capability $r entity_interfaces]
check invalid-formal-code INTERFACE_INVALID_OPERATOR [codes $r interface_diagnostics]
set r [inline operator-ordinary-invalid {package p is function "bad"(x : integer) return integer; end;}]
check invalid-ordinary-status malformed [capability $r subprogram_specifications]
set item [lindex [dict get [lindex [dict get $r object_declarations] 0] subprograms] 0]
check invalid-ordinary-code SUBPROGRAM_INVALID_OPERATOR [dict get [lindex [dict get $item diagnostics] 0] code]

foreach edition {1993 2002 2008} {
    set r [inline legal-operator {package p is function "AnD"(x, y : integer) return integer; end;} $edition]
    check "$edition letter operator parsed" parsed [capability $r subprogram_specifications]
    check "$edition exact spelling" {"AnD"} [lindex [routines $r] 0]
}
set r [inline formal-operator {entity e is generic (function "?="(a,b : integer) return boolean); end;}]
check matching-formal parsed [capability $r entity_interfaces]
foreach edition {1993 2002} {
    set r [inline alternate-operator {package body p is
    function %AnD%(x,y : integer) return integer is begin return x; end function "and"; end;} $edition]
    check "$edition alternate spelling" %AnD% [lindex [routines $r] 0]
    check "$edition alternate end matching" parsed [capability $r subprogram_bodies]
    set r [inline matching-operator {package p is function "?="(x,y : integer) return boolean; end;} $edition]
    check "$edition matching operator unavailable" recognized-but-unsupported [capability $r subprogram_specifications]
}
puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
