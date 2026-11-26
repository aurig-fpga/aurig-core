# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set assertions 0
set failures 0
proc check {label expected actual} {
    incr ::assertions
    if {$expected ne $actual} {
        incr ::failures
        puts [list FAIL $label expected $expected actual $actual]
    }
}
proc fixture {name {edition 2008}} {
    return [::vhdl_index::analyze_file [file join $::tests fixtures $name.vhd.fixture] $edition]
}
proc surface {result span} {
    if {$span eq {}} {return {}}
    return [::vhdl_index::slice [dict get $result snapshot] $span]
}
proc field {result item key} {
    if {![dict exists $item $key]} {return {}}
    return [surface $result [dict get $item $key]]
}
proc contains {outer inner} {
    if {$inner eq {}} {return 1}
    lassign $outer low high
    lassign $inner start finish
    return [expr {$low <= $start && $start < $finish && $finish <= $high}]
}
proc inventory {r} {
    set scopes {}
    foreach scope [dict get $r object_declarations] {dict set scopes [dict get $scope id] $scope}
    set names {}
    foreach scope [dict get $r object_declarations] {
        set id [dict get $scope id]
        check scope-open $id [lindex [dict get $scope span] 0]
        if {[dict get $scope parent_id] ne {}} {
            check parent-owns-child 1 [contains [dict get $scopes [dict get $scope parent_id] span] [dict get $scope span]]
        }
        set region [dict get $scope declarative_span]
        set previous [lindex $region 0]
        set claims {}
        foreach entry [dict get $scope entries] {
            for {set index 0} {$index < [lindex $entry 1]} {incr index} {
                set object [::vhdl_index::object::record $r $scope $entry $index]
                lappend claims [dict get $object span]
            }
        }
        foreach item [dict get $scope types] {
            set extent [dict get $item span]
            set name [field $r $item name_span]
            check "$name owner id" $id [dict get $item owner_id]
            check "$name owned extent" 1 [contains $region $extent]
            check "$name source order" 1 [expr {$previous <= [lindex $extent 0]}]
            set previous [lindex $extent 1]
            dict for {key value} $item {
                if {[string match *_span $key]} {check "$name $key containment" 1 [contains $extent $value]}
            }
            lappend claims $extent
            lappend names [list [dict get $scope kind] [field $r $scope name_span] $name $item]
        }
        set previous [lindex $region 0]
        foreach extent [lsort -integer -index 0 $claims] {
            check direct-claims-disjoint 1 [expr {$previous <= [lindex $extent 0]}]
            set previous [lindex $extent 1]
        }
    }
    set previous 0
    foreach row [dict get $r ledger] {
        check root-ledger-gapless $previous [lindex $row 1]
        set previous [lindex $row 2]
    }
    check root-ledger-end [dict get $r snapshot length] $previous
    return $names
}
proc index_by_name {records} {
    set result {}
    foreach row $records {dict lappend result [lindex $row 2] [lindex $row 3]}
    return $result
}
proc codes {result domain} {
    set resultCodes {}
    foreach issue [dict get $result ${domain}_diagnostics] {lappend resultCodes [dict get $issue code]}
    return $resultCodes
}
proc inline {name text edition} {
    file mkdir $::env(AURIG_EXPERIMENTAL_SCRATCH)
    set path [file join $::env(AURIG_EXPERIMENTAL_SCRATCH) $name.vhd]
    set channel [open $path w]
    puts $channel $text
    close $channel
    return [::vhdl_index::analyze_file $path $edition]
}

set r [fixture types]
set rows [inventory $r]
set stateName [format %cState%c%cSet%c 92 92 92 92]
set commaName [format "%cComma, and ;%c" 92 92]
set expected {
    {package type_catalog simple}
    {package type_catalog selected_mark}
    {package type_catalog bounded}
    {package type_catalog descending}
    {package type_catalog fraction}
    {package type_catalog slots}
    {package type_catalog distance}
    {package type_catalog samples}
    {package type_catalog cell}
    {package type_catalog link}
    {package type_catalog cell}
    {package type_catalog numbers_file}
    {package_body type_catalog body_only}
    {function f fn}
    {procedure p proc_t}
    {entity typed ent}
    {architecture structure arch_t}
    {package hidden_package nested_package_t}
    {process p proc_local}
    {process p proc_state}
    {block b nested_block_t}
    {generate_alternative {} nested_generate_t}
    {generate_alternative {} nested_alternative_t}
}
set actual {}
foreach row $rows {lappend actual [lrange $row 0 2]}
check type-inventory [linsert $expected 0 [list package type_catalog $stateName]] $actual
check no-type-issues {} [codes $r type]
check type-capability parsed [dict get $r capabilities type_declarations]
check declarations-opaque opaque [dict get $r capabilities declarations]
check expressions-opaque opaque [dict get $r capabilities expressions]
set byName [index_by_name $rows]
set item [lindex [dict get $byName $stateName] 0]
check enum-category enumeration [dict get $item kind]
check enum-opening {(} [field $r $item open_span]
check enum-closing {)} [field $r $item close_span]
check enum-terminator {;} [field $r $item terminator_span]
check enum-header "type $stateName is" [field $r $item header_span]
set literals {}
foreach literal [dict get $item literals] {
    lassign $literal kind span
    lappend literals [list $kind [surface $r $span]]
}
set expectedLiterals [list [list identifier Ready] [list extended_identifier $commaName]]
foreach char [list ( ) , {;} {"} '] {
    lappend expectedLiterals [list character "'$char'"]
}
check enum-literals $expectedLiterals $literals
set separators {}
foreach span [dict get $item separator_spans] {lappend separators [surface $r $span]}
check enum-separators [lrepeat 7 ,] $separators
set item [lindex [dict get $byName selected_mark] 0]
check subtype-definition {std.standard.integer range -2 to 9} [field $r $item subtype_span]
check subtype-mark std.standard.integer [field $r $item type_mark_span]
check subtype-constraint {range -2 to 9} [field $r $item constraint_span]
check subtype-header {subtype selected_mark is} [field $r $item header_span]
check subtype-end {;} [field $r $item terminator_span]
foreach {name direction left right} {bounded to {(1 + 2)} 7 descending downto 5 -1 fraction to -1.5 +1.5} {
    set item [lindex [dict get $byName $name] 0]
    check "$name kind" scalar_range [dict get $item kind]
    check "$name direction" $direction [dict get $item direction]
    check "$name direction spelling" $direction [field $r $item direction_span]
    check "$name left" $left [field $r $item left_bound_span]
    check "$name right" $right [field $r $item right_bound_span]
    check "$name range" "range $left $direction $right" [field $r $item range_span]
}
foreach {name kind} {distance physical samples array link access numbers_file file} {
    set item [lindex [dict get $byName $name] 0]
    check "$name typed envelope" $kind [dict get $item kind]
    set expectedStatus [expr {$kind in {array record physical access file} ? "parsed" : "recognized-but-unsupported"}]
    check "$name status" $expectedStatus [dict get $item status]
    check "$name terminator" {;} [field $r $item terminator_span]
}
set item [lindex [dict get $byName distance] 0]
check physical-envelope 1 [string match {*units*long_tick = 10 tick;*end units distance} [field $r $item definition_span]]
check physical-direction to [field $r $item direction_span]
set incomplete [lindex [dict get $byName cell] 0]
check incomplete-kind incomplete [dict get $incomplete kind]
check incomplete-status parsed [dict get $incomplete status]
check incomplete-definition {} [field $r $incomplete definition_span]
check incomplete-extent {type cell;} [field $r $incomplete span]
check record-kind record [dict get [lindex [dict get $byName cell] 1] kind]

set r [fixture types-resolution]
set byName [index_by_name [inventory $r]]
foreach {name kind resolution mark constraint} {
    resolved_bit scalar resolve_bit std.standard.bit {}
    vector_elements composite {(resolve_bit)} bit_vector {(3 downto 0)}
    matrix_shape {} {} matrix_t {(1 to 2)(7 downto 0)}
    from_attribute {} {} selected_vector'subtype {}
} {
    set item [lindex [dict get $byName $name] 0]
    set form {}
    if {[dict exists $item resolution_kind]} {set form [dict get $item resolution_kind]}
    check "$name resolution kind" $kind $form
    check "$name resolution" $resolution [field $r $item resolution_span]
    check "$name mark" $mark [field $r $item type_mark_span]
    check "$name constraint" $constraint [field $r $item constraint_span]
}
set r [fixture types-record-resolution]
set item [lindex [dict get [index_by_name [inventory $r]] pair_elements] 0]
check record-resolution {(left_element resolve_bit, right_element resolve_bit)} [field $r $item resolution_span]
foreach edition {1993 2002} {
    set r [fixture types-resolution $edition]
    check "$edition composite resolution" EDITION_COMPOSITE_RESOLUTION [lindex [codes $r type] 0]
    check "$edition chained constraint" 1 [expr {"EDITION_ELEMENT_CONSTRAINT" in [codes $r type]}]
    check "$edition type-mark attribute" 1 [expr {"EDITION_SUBTYPE_ATTRIBUTE" in [codes $r type]}]
}
foreach edition {1993 2002 2008} {
    set r [fixture types-editions $edition]
    check "$edition basic scalars" parsed [dict get $r capabilities type_declarations]
    check "$edition inventory" 5 [llength [inventory $r]]
}
foreach edition {2002 2008} {
    set r [fixture types-protected $edition]
    set byName [index_by_name [inventory $r]]
    check "$edition protected type" protected [dict get [lindex [dict get $byName lock] 0] kind]
    check "$edition protected body" protected_body [dict get [lindex [dict get $byName lock] 1] kind]
    check "$edition separate nested names" {lock after_lock private_t deeper} [dict keys $byName]
    check "$edition protected coverage" parsed [dict get $r capabilities type_declarations]
}
set r [fixture types-protected 1993]
check protected-1993-coverage unrecognized [dict get $r capabilities type_declarations]
set r [inline protected-package {package p is type t is protected body end protected body; end;} 2008]
check protected-body-scope TYPE_PROTECTED_BODY_OUT_OF_SCOPE [lindex [codes $r type] 0]

set r [fixture types-recovery]
set byName [index_by_name [inventory $r]]
check malformed-type-codes {TYPE_EXPECTED_NAME TYPE_EXPECTED_NAME TYPE_EXPECTED_ENUMERATION_SEPARATOR TYPE_EXPECTED_ENUMERATION_LITERAL TYPE_EXPECTED_ENUMERATION_LITERAL TYPE_EXPECTED_IS TYPE_EXPECTED_TYPE_DEFINITION TYPE_EXPECTED_RANGE_DIRECTION TYPE_EMPTY_PAYLOAD TYPE_MULTIPLE_RANGE_DIRECTIONS TYPE_MISSING_SEMICOLON TYPE_UNPROVEN_DECLARATION_BOUNDARY} [codes $r type]
check malformed-type-status unrecognized [dict get $r capabilities type_declarations]
check no-terminator {} [field $r [lindex [dict get $byName no_terminator] 0] terminator_span]
check recovered-type parsed [dict get [lindex [dict get $byName recovered] 0] status]
check uncertain-type unrecognized [dict get [lindex [dict get $byName unknown] 0] status]
check object-recovery-codes {OBJECT_MISSING_SEMICOLON OBJECT_OPAQUE_BOUNDARY} [codes $r object]
set r [fixture types-unsafe]
check unsafe-type unrecognized [dict get $r capabilities type_declarations]
check unsafe-keeps-proved {outside} [dict keys [index_by_name [inventory $r]]]
check unsafe-provenance TYPE_UNPROVEN_SCOPE [lindex [codes $r type] 0]

set r [inline attribute-range {package p is
    constant v : bit_vector(0 to 3) := "0000";
    type a is range v'range;
    type b is range v'reverse_range(1);
    type c is range v'length to (v'length + 2);
end;} 2008]
set byName [index_by_name [inventory $r]]
check attribute-range-status parsed [dict get $r capabilities type_declarations]
check range-attribute {v'range} [field $r [lindex [dict get $byName a] 0] range_attribute_span]
check reverse-range-attribute {v'reverse_range(1)} [field $r [lindex [dict get $byName b] 0] range_attribute_span]
check attribute-in-bound {v'length} [field $r [lindex [dict get $byName c] 0] left_bound_span]
set r [inline absent {entity e is signal s : bit; end;} 2008]
check verified-absence parsed [dict get $r capabilities type_declarations]
check verified-absence-rows {} [inventory $r]

set fixtureNames [lsort [glob -tails -directory [file join $tests fixtures] *.vhd.fixture]]
check isolated-fixture-count 83 [llength $fixtureNames]
check no-production-vhdl-fixtures {} [glob -nocomplain -directory [file join $tests fixtures] *.vhd *.vhdl]
puts [list Tcl [info patchlevel] assertions $assertions failures $failures]
exit [expr {$failures > 0}]
