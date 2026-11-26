# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]

foreach edition {1993 2002 2008} {
    set r [scope_input {entity e is begin process begin wait; end process; end;
    architecture a of e is begin
        p: postponed process (clk, data(3 downto 1), r.member) is
            type local_type is (one, two);
            procedure helper is variable pvar : local_type; begin null; end procedure;
            variable v : local_type;
        begin
            assert true;
            helper;
        end postponed process P;
        process begin null; end process;
    end;} $edition]
    set v [::vhdl_index::regions::view $r]
    set e [scope_find $v entity {entity e}]
    set a [scope_find $v architecture {architecture a}]
    check entity_processes 1 [llength [scope_rows $v $e process_headers]]
    check architecture_processes 2 [llength [scope_rows $v $a process_headers]]
    lassign [scope_rows $v $a process_headers] p bare
    foreach {key expected} {
        label_span p postponed_span postponed process_span process is_span is begin_span begin
        end_span end end_postponed_span postponed end_process_span process end_name_span P semicolon_span {;}
    } {
        check $key $expected [surface $r [dict get $p $key]]
    }
    check sensitivity_absent {} [dict get $bare sensitivity]
    set sense [dict get $p sensitivity]
    set names {}
    foreach name [dict get $sense name_spans] {lappend names [surface $r $name]}
    check names {clk {data(3 downto 1)} r.member} $names
    check count 1 [llength [scope_rows $v $a sensitivity_lists]]
    check opaque opaque [dict get $p sequential_status]
    check body {assert true;
            helper;} [string trim [surface $r [dict get $p sequential_span]]]
    set process [scope_find $v process p:]
    check occurrence $process [dict get $p occurrence_id]
    check owning_region $a [dict get $p owner_occurrence_id]
    check type_local 1 [llength [scope_rows $v $process type_declarations]]
    check object_local 1 [llength [scope_rows $v $process object_declarations]]
    set helper [scope_find $v procedure {procedure helper}]
    check helper_object 1 [llength [scope_rows $v $helper object_declarations]]
    check no_sequential_assertions 0 [llength [scope_rows $v $a concurrent_assertions]]
    scope_integrity $r $v
}
foreach {header edition status issue} {
    {process (all)} 2008 parsed {}
    {process (all)} 2002 malformed EDITION_PROCESS_ALL
    {process ()} 2008 malformed PROCESS_SENSITIVITY_MISSING_NAME
    {process (a,)} 2008 malformed PROCESS_SENSITIVITY_MISSING_NAME
    {process (all, a)} 2008 malformed PROCESS_SENSITIVITY_INVALID_ALL
    {process (2, a)} 2008 malformed PROCESS_SENSITIVITY_MISSING_TARGET
    {process (a} 2008 malformed PROCESS_SENSITIVITY_UNCLOSED_GROUP
} {
    set r [scope_input "entity e is end; architecture a of e is begin p: $header begin null; end process; keep: component c; end;" $edition]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    check retained_headers complete [scope_complete $v $a process_headers]
    set sensitivity [lindex [scope_rows $v $a sensitivity_lists] 0]
    check status $status [dict get $sensitivity status]
    if {$issue ne {}} {
        check issue $issue [dict get [lindex [dict get $sensitivity diagnostics] 0] code]
        check partial partial [scope_complete $v $a sensitivity_lists]
    } else {
        check all all [surface $r [dict get $sensitivity all_span]]
        check names {} [dict get $sensitivity name_spans]
    }
    check instance 1 [llength [scope_rows $v $a instantiations]]
    scope_integrity $r $v
}

foreach {header closing expectedSensitivity} {
    {process} {end process wrong;} complete
    {process (all)} {end process wrong;} partial
    {process (a)} {end postponed process;} partial
} {
    set r [scope_input "entity e is end; architecture a of e is begin p: $header variable x : bit; begin null; $closing keep: component c; end;"]
    set v [::vhdl_index::regions::view $r]
    set a [scope_find $v architecture {architecture a}]
    set p [scope_find $v process p:]
    check withdrawn withdrawn [dict get [::vhdl_index::regions::region $v $p] availability]
    check direct_partial partial [scope_complete $v $a process_headers]
    check no_process_row {} [scope_rows $v $a process_headers]
    check sensitivity_loss $expectedSensitivity [scope_complete $v $a sensitivity_lists]
    check no_sensitivity_row {} [scope_rows $v $a sensitivity_lists]
    check no_objects {} [scope_rows $v $p object_declarations]
    check safe_instance 1 [llength [scope_rows $v $a instantiations]]
    scope_integrity $r $v
}
puts {Process header and sensitivity assertions passed}
