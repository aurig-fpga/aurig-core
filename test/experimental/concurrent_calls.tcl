# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

proc lmap_surface {result spans} {
    set text {}
    foreach span $spans {lappend text [surface $result $span]}
    return $text
}

foreach edition {1993 2002 2008} {
    set r [scope_input {entity e is begin q: target; end;
    architecture a of e is begin
        target; q: postponed target;
        r: pkg.target(f(1, 2), note => "port map");
        u: target;
        i: target port map (open);
    end;} $edition]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set e [scope_find $v entity {entity e}]
    check entity_calls 1 [llength [scope_rows $v $e concurrent_procedure_calls]]
    set out [::vhdl_index::query::direct $v $a concurrent_procedure_calls]
    check call_inventory partial [dict get $out completeness]
    check ambiguity {component_instantiation concurrent_procedure_call} [dict get [lindex [dict get $out evidence] 0] forms]
    check instance_inventory partial [scope_complete $v $a instantiations]
    lassign [dict get $out rows] bare delayed actual
    check bare_name target [surface $r [dict get $bare called_name_span]]
    check bare_actuals {} [dict get $bare actual_parameters]
    check postponed postponed [surface $r [dict get $delayed postponed_span]]
    check called_name pkg.target [surface $r [dict get $actual called_name_span]]
    check components {pkg target} [lmap_surface $r [dict get $actual called_name_components]]
    set parameters [dict get $actual actual_parameters]
    check open ( [surface $r [dict get $parameters open_span]]
    check close ) [surface $r [dict get $parameters close_span]]
    check separator , [surface $r [lindex [dict get $parameters separator_spans] 0]]
    lassign [scope_rows $v $a actual_parameter_associations] positional named
    check positional positional [dict get $positional form]
    check nested {f(1, 2)} [surface $r [dict get $positional actual_span]]
    check named note [surface $r [dict get $named formal_span]]
    check connector => [surface $r [dict get $named arrow_span]]
    check called_occurrence [dict get $actual occurrence_id] [dict get $named call_occurrence_id]
    check maps 1 [llength [scope_rows $v $a map_associations]]
    check proved_maps complete [scope_complete $v $a map_associations]
    scope_integrity $r $v
}
foreach {bad calls actuals code} {
    {p(x => , y => 2,);} 2 1 PROCEDURE_CALL_MISSING_ACTUAL
    {p(x => open, 2);} 2 1 PROCEDURE_CALL_POSITIONAL_AFTER_NAMED
    {p(inertial y);} 2 0 PROCEDURE_CALL_INERTIAL_CONTEXT
    {p();} 2 0 PROCEDURE_CALL_MISSING_ELEMENT
    {p(x; } 1 0 PROCEDURE_CALL_EXPECTED_ASSOCIATION_CLOSE
    {q: (x);} 1 0 PROCEDURE_CALL_EXPECTED_NAME
} {
    set r [scope_input "entity e is end; architecture a of e is begin $bad keep: component c; q; end;"]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set out [::vhdl_index::query::direct $v $a actual_parameter_associations]
    check partial partial [dict get $out completeness]
    check calls $calls [llength [scope_rows $v $a concurrent_procedure_calls]]
    check actuals $actuals [llength [dict get $out rows]]
    set proof [lindex [dict get $out evidence] 0]
    check diagnostic $code [dict get [lindex [dict get $proof diagnostics] 0] code]
    check safe_instance 1 [llength [scope_rows $v $a instantiations]]
    scope_integrity $r $v
}
puts {Concurrent procedure call assertions passed}
