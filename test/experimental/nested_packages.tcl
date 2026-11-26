# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests scope_checks.tcl]
set text {package outer is
    package empty is end empty;
    package template is
        generic (n : positive; type element);
        package inner is end package inner;
        package instance is new work.template generic map (n => n, element => element);
    end package template;
end package outer;
package body outer is
    package implementation is end;
    package body implementation is end package body implementation;
end package body;}
set r [scope_input $text]
set v [::vhdl_index::regions::view $r]
check roots 2 [llength [::vhdl_index::query::units $v]]
set outer [scope_find $v package {package outer}]
check nested 2 [llength [scope_rows $v $outer package_declarations]]
set empty [scope_find $v package {package empty}]
check empty complete [scope_complete $v $empty object_declarations]
set template [scope_find $v package {package template}]
check parent $outer [dict get [::vhdl_index::regions::region $v $template] parent_id]
set shape [scope_shape $v $template]
check head {package template is} [surface $r [dict get $shape header_span]]
check close template [surface $r [dict get $shape end_name_span]]
check generic_items 2 [llength [dict get [lindex [scope_rows $v $template package_interfaces] 0] items]]
set inner [scope_find $v package {package inner}]
check inner_parent $template [dict get [::vhdl_index::regions::region $v $inner] parent_id]
set instance [lindex [scope_rows $v $template package_instantiations] 0]
check target work.template [surface $r [dict get $instance referenced_name_span]]
check map {generic map (n => n, element => element)} [surface $r [dict get $instance generic_map span]]
check separator {;} [surface $r [dict get $instance terminator_span]]
set packageBody [scope_find $v package_body {package body implementation}]
check empty_body complete [scope_complete $v $packageBody object_declarations]
scope_integrity $r $v
foreach edition {1993 2002} {
    set r [scope_input {package p is package q is end; end;} $edition]
    check old_edition EDITION_NESTED_PACKAGE [scope_error $r]
    set r [scope_input {package p is generic (n : integer); end;} $edition]
    check old_generic EDITION_PACKAGE_GENERIC [scope_error $r]
}
foreach {source cause} {
    {package p is package is end; end;} EXPECTED_NAME
    {package p is package q is new work.template end;} EXPECTED_TOKEN
    {package p is package body q is end; end;} NESTED_PACKAGE_OUT_OF_CONTEXT
    {package p is package q is end package p; package unrelated is end;} ANCESTOR_END_NAME
} {
    set r [scope_input $source]
    check recovery $cause [scope_error $r]
    scope_integrity $r [::vhdl_index::regions::view $r]
}
set r [scope_input {package p is package q is package inner is end; end package wrong;
    package sibling is end; end;}]
set v [::vhdl_index::regions::view $r]
set q [scope_find $v package {package q}]
set sibling [scope_find $v package {package sibling}]
check mismatch MISMATCHED_END_NAME [scope_error $r]
check withdrawn unavailable [scope_complete $v $q object_declarations]
check independent complete [scope_complete $v $sibling object_declarations]
check mask unrecognized [dict get $r capabilities package_declarations]
scope_integrity $r $v
puts "Nested package ownership assertions passed"
