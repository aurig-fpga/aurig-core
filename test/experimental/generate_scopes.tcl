# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]
set r [::vhdl_index::analyze_file [file join $tests fixtures structural-generate.vhd.fixture] 2008]
set v [::vhdl_index::regions::view $r]
set forId [scope_find $v for_generate g:]
set ifId [scope_find $v if_generate choose:]
set caseId [scope_find $v case_generate c:]
set p [lindex [scope_rows $v $forId generate_parameters] 0]
check parameter_role generate_parameter [lindex [dict get $p occurrence_id] 1]
check parameter_owner $forId [dict get $p owner_occurrence_id]
check parameter i [surface $r [dict get $p name_span]]
check connector in [surface $r [dict get $p in_span]]
set range [dict get $p range]
check range {natural range 0 to 3} [surface $r [dict get $range span]]
check range_bounds {0 to 3} [list [surface $r [dict get $range left_bound_span]] \
    [dict get $range direction] [surface $r [dict get $range right_bound_span]]]
check one_explicit_object 1 [llength [scope_rows $v $forId object_declarations]]
check for_end {end generate g;} [surface $r [dict get [scope_shape $v $forId] terminator_span]]
set head [scope_find $v generate_alternative {if head:}]
set middle [scope_find $v generate_alternative {elsif middle:}]
set tail [scope_find $v generate_alternative {else tail:}]
foreach id [list $head $middle $tail] {
    check alt_parent $ifId [dict get [::vhdl_index::regions::region $v $id] parent_id]
}
check condition {i = 0} [surface $r [dict get [scope_shape $v $head] condition_span]]
check label_end {end head;} [surface $r [dict get [scope_shape $v $head] terminator_span]]
check alt_objects 1 [llength [scope_rows $v $head object_declarations]]
check dup_alt_objects 1 [llength [scope_rows $v $middle object_declarations]]
check empty_complete complete [scope_complete $v $tail object_declarations]
check empty_rows {} [scope_rows $v $tail object_declarations]
check subtree_objects 3 [llength [dict get [::vhdl_index::query::subtree $v $ifId object_declarations] rows]]
set digits [scope_find $v generate_alternative {when digits:}]
set others [scope_find $v generate_alternative {when others}]
check case_parent $caseId [dict get [::vhdl_index::regions::region $v $digits] parent_id]
check choice_separator | [surface $r [lindex [dict get [scope_shape $v $digits] separator_spans] 0]]
check choice_ranges {0 {1 to 2}} [choice_surfaces $r [dict get [scope_shape $v $digits] choices]]
check others others [dict get [lindex [dict get [scope_shape $v $others] choices] 0] kind]
scope_integrity $r $v

foreach edition {1993 2002 2008} {
    set r [scope_input {entity e is end; architecture a of e is begin
        i: if true generate begin end generate;
        f: for k in 1 to 2 generate constant c : integer := k; begin end generate;
    end;} $edition]
    set vv [::vhdl_index::regions::view $r]
    check old_begin complete [scope_complete $vv [scope_find $vv for_generate f:] object_declarations]
    check snapshot_foreign 1 [catch {scope_complete $vv $forId object_declarations} _ options]
    check identity_error {VHDL_INDEX REGION_ID} [dict get $options -errorcode]
}
foreach {body cause} {
    {a: for in 0 to 1 generate end generate;} EXPECTED_NAME
    {a: if true end generate;} INCOMPLETE_GENERATE_HEADER
    {a: case 0 generate when 0 begin end generate;} INCOMPLETE_GENERATE_HEADER
    {a: if true generate b: block begin end generate;} MISMATCHED_END_KIND
    {a: if true generate end; elsif false generate end generate;} EDITION_GENERATE_BODY_END
} {
    set edition [expr {$cause eq "EDITION_GENERATE_BODY_END" ? 2002 : 2008}]
    set r [scope_input "entity e is end; architecture a of e is begin $body end;" $edition]
    check malformed $cause [scope_error $r]
    scope_integrity $r [::vhdl_index::regions::view $r]
}
set r [scope_input {entity e is end; architecture a of e is begin
    g: if missing: generate
        t: block begin end block;
    end missing;
    elsif 1: false generate end;
    elsif okay: false generate begin end okay;
    else generate end;
    end generate g;
    next_gen: case 0 generate when 0 | => end; when others => end; end generate;
    bad: if named: true generate end wrong; else generate end generate wrong_outer;
end;}]
set v [::vhdl_index::regions::view $r]
foreach first {{if missing:} {elsif 1:} {when 0 |} {if named:}} {
    set id [scope_find $v generate_alternative $first]
    check withdrawn unavailable [scope_complete $v $id object_declarations]
}
foreach first {{elsif okay:} {else generate} {when others}} {
    set id [scope_find $v generate_alternative $first]
    check sibling_complete complete [scope_complete $v $id object_declarations]
}
check global_loss unrecognized [dict get $r capabilities object_declarations]
scope_integrity $r $v
puts "Generate ownership assertions passed"
