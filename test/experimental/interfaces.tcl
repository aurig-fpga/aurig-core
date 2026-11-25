source [file join [file dirname [info script]] startup.tcl]
set checks 0
set failures 0

proc eq_test {tag want have} {
    incr ::checks
    if {$want ne $have} {
        incr ::failures
        puts [list FAIL $tag expected $want actual $have]
    }
}
proc part {r span} {
    if {$span eq {}} {return {}}
    return [::vhdl_index::slice [dict get $r snapshot] $span]
}
proc obj {r record key} {
    return [part $r [dict get $record $key]]
}
proc names {r item {fold 0}} {
    set out {}
    foreach s [dict get $item names] {
        set name [part $r $s]
        if {$fold} {set name [string tolower $name]}
        lappend out $name
    }
    return $out
}
proc codes {r} {
    set codes {}
    foreach d [dict get $r interface_diagnostics] {lappend codes [dict get $d code]}
    return $codes
}
proc inventory {r} {
    set out {}
    foreach u [dict get $r units] {lappend out [dict get $u name]}
    return $out
}
proc input {relative {edition 2008}} {
    if {[lindex [file split $relative] 0] eq "fixtures"} {
        set root $::tests
    } else {
        set root $::archivedTask
    }
    return [::vhdl_index::analyze_file [file join $root $relative] $edition]
}
proc records {result {index 0}} {
    return [dict get [lindex [dict get $result entity_interfaces] $index] clauses]
}
proc contains {tag outer inner} {
    if {$inner eq {}} {return}
    lassign $outer lo hi
    lassign $inner start end
    eq_test "$tag interval" 1 [expr {$lo <= $start && $start <= $end && $end <= $hi}]
}
proc ordered {tag parent spans} {
    set last [lindex $parent 0]
    foreach s $spans {
        contains $tag $parent $s
        eq_test "$tag order" 1 [expr {[lindex $s 0] >= $last}]
        set last [lindex $s 1]
    }
}
proc list_geometry {r tag outer record} {
    set spans {}
    foreach item [dict get $record items] {
        set region [dict get $item span]
        lappend spans $region
        ordered "$tag names" $region [dict get $item names]
        dict for {key value} $item {
            if {[string match *_span $key]} {contains "$tag $key" $region $value}
            if {[string match *_spans $key]} {ordered "$tag $key" $region $value}
        }
        if {[dict exists $item parameters]} {
            list_geometry $r "$tag parameters" $region [dict get $item parameters]
        }
        if {[dict exists $item colon_span]} {
            eq_test "$tag colon" : [obj $r $item colon_span]
        }
    }
    ordered "$tag items" $outer $spans
    if {[dict exists $record open_span]} {
        foreach k {open_span close_span} spelling {( )} {
            contains "$tag $k" $outer [dict get $record $k]
            eq_test "$tag $k" $spelling [obj $r $record $k]
        }
        lassign [dict get $record open_span] _ lo
        lassign [dict get $record close_span] hi _
        ordered "$tag contents" [list $lo $hi] $spans
        ordered "$tag separators" [list $lo $hi] [dict get $record separator_spans]
        foreach separator [dict get $record separator_spans] {
            eq_test "$tag separator spelling" ";" [part $r $separator]
            foreach span $spans {
                eq_test "$tag separator disjoint" 1 [expr {
                    [lindex $span 1] <= [lindex $separator 0] || [lindex $separator 1] <= [lindex $span 0]}]
            }
        }
    }
}
proc geometry {tag r} {
    set last 0
    set reconstructed {}
    foreach row [dict get $r ledger] {
        lassign $row state start end
        eq_test "$tag ledger adjacency" $last $start
        append reconstructed [part $r [list $start $end]]
        set last $end
    }
    eq_test "$tag root ledger reconstruction" [dict get $r snapshot text] $reconstructed
    set tape [dict get $r tape]
    set last 0
    set reconstructed {}
    for {set i 0} {$i < [llength [dict get $tape starts]]} {incr i} {
        lassign [::vhdl_index::lexer::token $tape $i] kind start end
        eq_test "$tag lexical adjacency" $last $start
        append reconstructed [part $r [list $start $end]]
        set last $end
    }
    eq_test "$tag tape reconstruction" [dict get $r snapshot text] $reconstructed
    eq_test "$tag EOF kind" eof $kind
    eq_test "$tag EOF span" [list $last $last] [list $start $end]
    set units {}
    foreach unit [dict get $r units] {
        if {[dict get $unit kind] eq "entity"} {dict set units [dict get $unit name_span] $unit}
    }
    foreach owner [dict get $r entity_interfaces] {
        set unit [dict get $units [dict get $owner owner_name_span]]
        eq_test "$tag identity" [dict get $r source_id] [dict get $owner source_id]
        eq_test "$tag owner extent" [dict get $unit span] [dict get $owner owner_span]
        set clauses {}
        foreach clause [dict get $owner clauses] {
            set span [dict get $clause span]
            lappend clauses $span
            list_geometry $r $tag $span $clause
            if {[dict exists $clause semicolon_span] && [dict get $clause semicolon_span] ne {}} {
                eq_test "$tag clause terminator" ";" [obj $r $clause semicolon_span]
            }
        }
        ordered "$tag clauses" [dict get $unit opaque] $clauses
    }
    eq_test "$tag expressions opaque" opaque [dict get $r capabilities expressions]
    eq_test "$tag declarations opaque" opaque [dict get $r capabilities declarations]
}

set manifest [open [file join $archivedTask raw interface-cases.tsv]]
while {[gets $manifest row] >= 0} {
    lassign [split $row "\t"] edition path status code
    set r [input $path $edition]
    eq_test "$path/$edition interface status" $status [dict get $r capabilities entity_interfaces]
    if {$code ne {}} {eq_test "$path/$edition diagnostic" 1 [expr {$code in [codes $r]}]}
    geometry "$path/$edition" $r
    if {[string match */legal-* $path]} {
        lassign [records $r] generic port
        set entries [dict get $generic items]
        eq_test "$path generics grouped" {first second} [names $r [lindex $entries 0] 1]
        eq_test "$path generic item order" {lit width} [list \
            {*}[names $r [lindex $entries 1] 1] {*}[names $r [lindex $entries 2] 1]]
        set entries [dict get $port items]
        eq_test "$path ports grouped" {a b} [names $r [lindex $entries 0] 1]
        eq_test "$path dest mode" out [dict get [lindex $entries 1] effective_mode]
    }
    if {$status eq "unrecognized"} {
        eq_test "$path no fictitious later design unit" {} [inventory $r]
        eq_test "$path unrecognized root present" 1 [expr {[dict get $r recovery] ne {}}]
    }
}
close $manifest

set rangeResult [input fixtures/interface-range-attribute.vhd]
set rangeGeneric [lindex [records $rangeResult] 0]
set indexItem [lindex [dict get $rangeGeneric items] 1]
eq_test range-attribute-constraint {natural range indices'range} [obj $rangeResult $indexItem subtype_span]

set offsets [input fixtures/interface-offsets.vhd]
lassign [records $offsets] bg bp
set item [lindex [dict get $bg items] 0]
eq_test exact-clause-offsets {12 40} [dict get $bg span]
eq_test exact-open-offsets {20 21} [dict get $bg open_span]
eq_test exact-close-offsets {38 39} [dict get $bg close_span]
eq_test exact-semicolon-offsets {39 40} [dict get $bg semicolon_span]
eq_test exact-group-offsets {{21 22} {24 25}} [dict get $item names]
eq_test exact-subtype-offsets {28 31} [dict get $item subtype_span]
eq_test exact-default-offsets {35 38} [dict get $item default_span]
eq_test exact-port-offsets {41 60} [dict get $bp span]

set scoped [input fixtures/interface-scopes.vhd]
eq_test two-entity-owners 2 [llength [dict get $scoped entity_interfaces]]
set scopedNames {}
foreach owner [dict get $scoped entity_interfaces] {
    lappend scopedNames [part $scoped [dict get $owner owner_name_span]]
    foreach clause [dict get $owner clauses] {
        foreach item [dict get $clause items] {lappend scopedNames {*}[names $scoped $item]}
    }
}
eq_test nested-maps-and-component-are-excluded {leaf width output wrapper out_bit} $scopedNames

set r [input fixtures/interface-basic.vhd 1993]
lassign [records $r] generic port
lassign [dict get $generic items] width label marker other
eq_test exact-group {WIDTH Depth} [names $r $width]
eq_test exact-explicit-class constant [dict get $width explicit_class]
eq_test exact-explicit-mode in [dict get $width explicit_mode]
eq_test exact-class-spelling constant [obj $r $width class_span]
eq_test exact-width-type natural [obj $r $width subtype_span]
eq_test exact-width-default 4 [obj $r $width default_span]
eq_test exact-spelling {"x);"";"} [obj $r $label default_span]
eq_test qualified-character {character '(')')} [obj $r $marker default_span]
eq_test quote-character {'"'} [obj $r $other default_span]
set tokens {}
set tape [dict get $r tape]
lassign [dict get $marker default_span] first last
for {set i 0} {$i < [llength [dict get $tape starts]]} {incr i} {
    lassign [::vhdl_index::lexer::token $tape $i] kind start end
    if {$start >= $first && $end <= $last && $kind ne "whitespace"} {lappend tokens $kind}
}
eq_test apostrophe-token-disambiguation {identifier ' ( character )} $tokens
lassign [dict get $port items] inputs result live shadow opaque
eq_test exact-extended [list source_a "\\B;Field\\"] [names $r $inputs]
eq_test exact-implicit-mode in [dict get $inputs effective_mode]
eq_test exact-implicit-mode-empty {} [dict get $inputs explicit_mode]
eq_test exact-selected-type std.standard.bit [obj $r $inputs subtype_span]
eq_test exact-constrained-type {bit_vector(WIDTH - 1 downto 0)} [obj $r $result subtype_span]
eq_test exact-default-aggregate {(others => '0')} [obj $r $result default_span]
eq_test bus-span bus [obj $r $live bus_span]
eq_test special-port-modes {inout buffer linkage} [list \
    [dict get $live effective_mode] [dict get $shadow effective_mode] [dict get $opaque effective_mode]]

set r [input fixtures/interface-2008.vhd]
lassign [records $r] generic port
set categories {}
foreach item [dict get $generic items] {lappend categories [dict get $item category]}
eq_test formal-categories {type subprogram subprogram subprogram package object} $categories
lassign [dict get $generic items] type plus reader sender map fill
eq_test operator-designator {"+"} [lindex [names $r $plus] 0]
eq_test parameter-keyword parameter [obj $r $plus parameter_keyword_span]
eq_test default-purity pure [dict get $plus effective_purity]
eq_test explicit-purity impure [dict get $reader effective_purity]
eq_test subprogram-default <> [obj $r $plus default_designator_span]
eq_test subprogram-return item [obj $r $plus return_type_span]
eq_test grouped-parameters {left right} [names $r [lindex [dict get $plus parameters items] 0]]
eq_test two-parameter-items 2 [llength [dict get $reader parameters items]]
eq_test package-target work.seed [obj $r $map package_target_span]
eq_test package-map {generic map (width => (2 + 2))} [obj $r $map map_span]
set matrix [lindex [dict get $port items] 0]
eq_test nested-array-constraints {fixed_map.table(0 to 1)(0 to 3)} [obj $r $matrix subtype_span]
eq_test nested-associations {(0 => (others => fill), others => (others => '1'))} [obj $r $matrix default_span]
set r [input fixtures/interface-package-special.vhd]
set clauses [records $r]
set forms {}
foreach item [dict get [lindex $clauses 0] items] {lappend forms [dict get $item map_kind]}
eq_test package-special-maps {default <>} $forms

set lexicalCase [input scratch/interfaces/lexically-bad-default-2008.vhd]
set lexicalItem [lindex [dict get [lindex [records $lexicalCase] 0] items] 0]
eq_test lexical-problem-invalidates-item malformed [dict get $lexicalItem status]

set r [input fixtures/interface-recovery.vhd]
eq_test safe-unit-recovery {fix later} [inventory $r]
lassign [records $r] generic port
eq_test semicolon-recovered-generic width [names $r [lindex [dict get $generic items] 1]]
eq_test missing-separator-recovered-group {suffix_a suffix_b} [names $r [lindex [dict get $generic items] 2]]
eq_test malformed-item-stays-malformed malformed [dict get [lindex [dict get $generic items] 0] status]
eq_test nested-semicolon-is-not-recovery-boundary 3 [llength [dict get $port items]]
eq_test outer-semicolon-proves-next-item b [names $r [lindex [dict get $port items] 2]]
eq_test later-entity-own-name later [part $r [dict get [lindex [dict get $r entity_interfaces] 1] owner_name_span]]

set r [input ../AURIG-004-A/fixtures/grouped-interface.vhd]
lassign [records $r] generic port
eq_test archived-grouped-AB {A B} [names $r [lindex [dict get $generic items] 0]]
eq_test archived-grouped-xy {x y} [names $r [lindex [dict get $port items] 0]]
eq_test archived-single-z z [names $r [lindex [dict get $port items] 1]]
set r [input ../../aurig-core/test/parser/fixtures/invalid_syntax/port_keyword_split.vhd]
eq_test core-split-keyword SPLIT_INTERFACE_KEYWORD [codes $r]
eq_test core-split-preserves-architecture {port_split rtl} [inventory $r]
set r [input ../../aurig-core/test/parser/fixtures/invalid_syntax/missing_semicolons.vhd]
eq_test core-root-before-interface unrecognized [dict get $r capabilities entity_interfaces]
set r [input ../../aurig-core/test/parser/fixtures/invalid_syntax/wrong_types.vhd]
eq_test wrong-types-semantic-limits parsed [dict get $r capabilities entity_interfaces]
set item [lindex [dict get [lindex [records $r] 0] items] 2]
eq_test not-a-mode {inward std_logic} [obj $r $item subtype_span]
eq_test mode-is-implicit in [dict get $item effective_mode]
eq_test aliases-allow-this-spelling parsed \
    [dict get [input fixtures/interface-resolution.vhd] capabilities entity_interfaces]

puts [list Tcl [info patchlevel] assertions $checks failures $failures]
exit [expr {$failures > 0}]
