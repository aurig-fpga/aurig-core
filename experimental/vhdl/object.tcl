# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::object {
    namespace path {::vhdl_index::grammar ::vhdl_index::parser}
}

proc ::vhdl_index::object::syntax {state ownerKind recordVar} {
    upvar 1 $state c $recordVar item
    set form [kind c]
    set first [take c]
    dict set item kind $form
    dict set item class_span $first
    dict set item keyword_span $first
    if {$form eq "shared"} {
        set form shared_variable
        dict set item kind $form
        dict set item shared_span $first
        dict set item keyword_span {}
        set keyword [require c variable EXPECTED_VARIABLE]
        dict set item keyword_span $keyword
        dict set item class_span [list [lindex $first 0] [lindex $keyword 1]]
    }

    lassign [identifier_list c] names commas colon
    dict set item names $names
    dict set item colon_span $colon
    lassign [subtype_indication c {bus register := {;} eof}] subtype constraint
    dict set item subtype_span $subtype
    dict set item constraint_span $constraint
    set qualifier [kind c]
    if {$qualifier in {bus register}} {
        dict set item qualifier $qualifier
        dict set item qualifier_span [take c]
    }
    if {[kind c] eq ":="} {
        dict set item init_marker_span [take c]
        dict set item init_span [payload c {{;} when else eof}]
    }
    set tail [kind c]
    if {$tail eq "eof"} {reject c MISSING_SEMICOLON}
    if {$tail in {when else}} {reject c EDITION_CONDITIONAL_INITIALIZER}
    dict set item terminator_span [require c {;} UNEXPECTED_TAIL]

    if {![allowed $ownerKind $form]} {
        dict lappend item diagnostics [at OBJECT_CLASS_OUT_OF_SCOPE $first]
    }
    if {[dict get $item qualifier_span] ne {} && $form ne "signal"} {
        dict lappend item diagnostics [at OBJECT_INVALID_SIGNAL_KIND [dict get $item qualifier_span]]
    }
    if {$form eq "constant" && [dict get $item init_marker_span] eq {}} {
        if {$ownerKind eq "package"} {
            dict set item deferred 1
        } else {
            dict lappend item diagnostics [at OBJECT_MISSING_INITIALIZATION $subtype]
        }
    }
}

proc ::vhdl_index::object::allowed {ownerKind form} {
    set local [expr {$ownerKind in {process function procedure}}]
    switch -- $form {
        variable {return $local}
        shared_variable {return [expr {!$local}]}
        signal {return [expr {!$local && $ownerKind ne "package_body"}]}
        default {return 1}
    }
}

proc ::vhdl_index::object::at {code extent} {
    return [dict create code $code severity error phase object span $extent]
}

proc ::vhdl_index::object::fields {owner} {
    return [dict create owner_id $owner kind {} span {} names {} class_span {} keyword_span {}         shared_span {} colon_span {} subtype_span {} constraint_span {} qualifier {} qualifier_span {}         init_marker_span {} init_span {} terminator_span {} deferred 0 status parsed diagnostics {}]
}

# The typed walk supplies a fence and reports any ambiguous declaration prefix.
proc ::vhdl_index::object::index {state ownerKind owner first} {
    upvar 1 $state c
    set c(grammarFence) $c(i)
    set c(grammarDomain) OBJECT
    set c(grammarPrefixes) {}
    set c(grammarNamePrefix) 0
    set c(i) $first
    if {$c(opaqueBoundary) ne {}} {
        set firstSpan [span c]
        set form [kind c]
        set c(i) $c(grammarFence)
        set region [extent c [lindex $firstSpan 0]]
        set issue [dict merge [at OBJECT_UNPROVEN_DECLARATION_BOUNDARY $region] \
            [dict create related_span $c(opaqueBoundary)]]
        set diagnostics [linsert [lexical_diagnostics c $region objectLexicalAt] 0 $issue]
        lappend c(objectDiagnostics) {*}$diagnostics
        set item [dict replace [fields $owner] kind $form span $region keyword_span $firstSpan \
            status unrecognized diagnostics $diagnostics]
        return [list [list [list $first 1 $item]] unrecognized]
    }
    # The common single-name, single-type-mark production needs no rich
    # fields. Check the complete fence and leave any lexical issue to the
    # ordinary production, which retains its provenance.
    set form [kind c]
    if {$c(grammarFence) - $first == 5 &&
        $c(objectLexicalAt) == [llength $c(declarationLexical)] &&
        $form ne "shared" && ($form ne "constant" || $ownerKind eq "package") &&
        [allowed $ownerKind $form] && [simple_declarator c]} {
        set c(i) $c(grammarFence)
        return [list [list [list $first 1]] parsed]
    }
    set start [lindex [span c] 0]
    set item [fields $owner]
    if {[catch {syntax c $ownerKind item} issue options]} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX OBJECT}} {
            return -options $options $issue
        }
        dict set issue phase object
        dict lappend item diagnostics $issue
        if {$c(i) + 1 == $c(grammarFence) && [kind c] eq ";"} {
            dict set item terminator_span [take c]
        }
        set c(i) $c(grammarFence)
    }
    set region [extent c $start]
    dict set item span $region
    dict lappend item diagnostics {*}[lexical_diagnostics c $region objectLexicalAt]
    foreach issue [dict get $item diagnostics] {
        set next malformed
        if {[string match EDITION_* [dict get $issue code]]} {set next recognized-but-unsupported}
        dict set item status [combine [dict get $item status] $next]
        lappend c(objectDiagnostics) $issue
    }
    set status [dict get $item status]
    # The five-token form can reconstruct every field from its ordinal.
    set entry [list $first 1]
    if {$status ne "parsed" || $c(i) - $first != 5} {lappend entry $item}
    return [list [list $entry] $status]
}

# Contiguous five-token records share an ordinal and a count. The capture
# uses the ordinary grammar before classifying an entry as compressible.
proc ::vhdl_index::object::append_entries {entriesVar records} {
    upvar 1 $entriesVar entries
    foreach row $records {
        lassign $row start count item
        lassign [lindex $entries end] prior length rich
        if {$item eq {} && $prior ne {} && $rich eq {} && $start == $prior + 5 * $length} {
            lset entries end 1 [expr {$length + 1}]
        } else {
            lappend entries $row
        }
    }
}

# Private view used by the experiment's assertion and comparison harnesses.
proc ::vhdl_index::object::record {result scope entry index} {
    lassign $entry first count item
    if {$item ne {}} {return $item}
    set ordinal [expr {$first + 5 * $index}]
    variable ::vhdl_index::lexer::labels
    set tape [dict get $result tape]
    set significant [dict get $tape significant]
    set starts [dict get $tape starts]
    set kinds [dict get $tape kinds]
    set keyword [lindex $significant $ordinal]
    set kind [lindex $labels [lindex $kinds $keyword]]
    foreach key {class names colon subtype terminator} offset {0 1 2 3 4} {
        set ix [lindex $significant [expr {$ordinal + $offset}]]
        set $key [list [lindex $starts $ix] [lindex $starts [expr {$ix + 1}]]]
    }
    set item [fields [dict get $scope id]]
    return [dict replace $item kind $kind span [list [lindex $class 0] [lindex $terminator 1]]         class_span $class keyword_span $class names [list $names] colon_span $colon subtype_span $subtype         terminator_span $terminator deferred [expr {$kind eq "constant"}]]
}
