# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]
set r [::vhdl_index::analyze_file [file join $tests fixtures structural-blocks.vhd.fixture] 2008]
set v [::vhdl_index::regions::view $r]
set outer [scope_find $v block outer:]
set inner [scope_find $v block inner:]
set a [scope_find $v architecture {architecture rtl}]
set shape [scope_shape $v $outer]
check label outer [surface $r [dict get $shape label_span]]
check guard {bus_in = '1'} [surface $r [dict get $shape guard_span]]
check connector is [surface $r [dict get $shape is_span]]
check block_begin begin [surface $r [dict get $shape begin_span]]
check closing {end block outer;} [surface $r [dict get $shape terminator_span]]
check end_name outer [surface $r [dict get $shape end_name_span]]
check formal_inventory 2 [llength [scope_rows $v $outer block_interfaces]]
check generic_map {limit => 3} [surface $r [dict get [lindex [dict get $shape maps] 0] association_span]]
check port_map {input => bus_in} [surface $r [dict get [lindex [dict get $shape maps] 1] association_span]]
check arch_objects 1 [llength [scope_rows $v $a object_declarations]]
check block_objects 1 [llength [scope_rows $v $outer object_declarations]]
check block_components 1 [llength [scope_rows $v $outer component_declarations]]
check block_subprograms 1 [llength [scope_rows $v $outer subprogram_bodies]]
check block_package 1 [llength [scope_rows $v $outer package_declarations]]
check nested_parent $outer [dict get [::vhdl_index::regions::region $v $inner] parent_id]
check opaque_statement complete [scope_complete $v $inner object_declarations]
check arc_subtree 3 [llength [dict get [::vhdl_index::query::subtree $v $a object_declarations] rows]]
scope_integrity $r $v

foreach edition {1993 2002 2008} {
    set r [scope_input {entity e is end; architecture a of e is begin b: block begin end block; end;} $edition]
    check editions 3 [llength [scope_find [::vhdl_index::regions::view $r] block b:]]
}
foreach {body cause} {
    {block begin end block;} MISSING_BLOCK_LABEL
    {b: block signal s : bit; end block;} MISSING_BEGIN
    {b: block port map (a); begin end block;} BLOCK_MAP_WITHOUT_CLAUSE
    {b: block generic (n : bit; begin end block;} INTERFACE_UNCLOSED_GROUP
    {b: block begin p: process begin wait; end block;} MISMATCHED_END_KIND
    {foo b: block begin end block;} UNPROVEN_CONCURRENT_BOUNDARY
} {
    set r [scope_input "entity e is end; architecture a of e is begin $body end;"]
    check recovery $cause [scope_error $r]
    scope_integrity $r [::vhdl_index::regions::view $r]
}
set r [scope_input {entity e is end; architecture a of e is begin
    b: block generic (n positive); signal s : bit; begin end block;
    c: block begin d: block begin end block; end block wrong;
    keep: block begin end block;
end;}]
set v [::vhdl_index::regions::view $r]
set b [scope_find $v block b:]
set c [scope_find $v block c:]
set keep [scope_find $v block keep:]
check malformed_formal partial [scope_complete $v $b block_interfaces]
check proved_locals complete [scope_complete $v $b object_declarations]
check withdrawn_interface unavailable [scope_complete $v $c block_interfaces]
check good_sibling complete [scope_complete $v $keep object_declarations]
scope_integrity $r $v
puts "Block ownership assertions passed"
