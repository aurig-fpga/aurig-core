# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::type_declaration {
    namespace path {::vhdl_index::grammar ::vhdl_index::parser}
}

proc ::vhdl_index::type_declaration::enumeration {state recordVar} {
    upvar 1 $state c $recordVar item
    dict set item open_span [require c ( EXPECTED_OPEN]
    set literals {}
    set separators {}
    while {1} {
        set token [kind c]
        if {![is_name $token 0] && $token ne "character"} {
            reject c EXPECTED_ENUMERATION_LITERAL
        }
        lappend literals [list $token [take c]]
        if {[kind c] ne ","} {break}
        lappend separators [take c]
    }
    dict set item literals $literals
    dict set item separator_spans $separators
    dict set item close_span [require c ) EXPECTED_ENUMERATION_SEPARATOR]
}

proc ::vhdl_index::type_declaration::composite_subtype {state stops} {
    upvar 1 $state c
    lassign [subtype_indication c $stops 1 1] subtype constraint mark resolution form
    return [dict create subtype_span $subtype type_mark_span $mark constraint_span $constraint \
        resolution_span $resolution resolution_kind $form]
}

proc ::vhdl_index::type_declaration::array_definition {state recordVar} {
    upvar 1 $state c $recordVar item
    dict set item array_keyword_span [require c array EXPECTED_ARRAY]
    set first [lindex [span c] 0]
    dict set item open_span [require c ( EXPECTED_ARRAY_OPEN]
    set dimensions {}
    set separators {}
    set shape {}
    while {1} {
        set ordinal $c(i)
        set dimension [discrete_range c 1]
        set form [expr {[dict get $dimension kind] eq "index_subtype" ? "unconstrained" : "constrained"}]
        if {$shape ne {} && $shape ne $form} {
            set c(i) $ordinal
            reject c MIXED_INDEX_CONSTRAINT
        }
        set shape $form
        lappend dimensions $dimension
        if {[kind c] ne ","} {break}
        lappend separators [take c]
    }
    dict set item array_kind $shape
    dict set item dimensions $dimensions
    dict set item separator_spans $separators
    dict set item close_span [require c ) EXPECTED_DIMENSION_SEPARATOR]
    dict set item index_span [extent c $first]
    dict set item of_span [require c of EXPECTED_ARRAY_OF]
    set item [dict merge $item [composite_subtype c {{;} eof}]]
}

# The typed boundary walk already proved the outer envelope. A complex
# definition is skipped using its fence, including any nested terminators.
proc ::vhdl_index::type_declaration::syntax {state ownerKind category recordVar} {
    upvar 1 $state c $recordVar item
    set keyword [kind c]
    set intro [take c]
    set start [lindex $intro 0]
    dict set item keyword_span $intro
    dict set item kind $keyword
    dict set item name_span [name_span c]
    dict set item header_span [extent c $start]
    if {$keyword eq "type" && [kind c] in {{;} eof}} {
        dict set item kind incomplete
    } else {
        dict set item is_span [require c is EXPECTED_IS]
        dict set item header_span [extent c $start]
        set definition [lindex [span c] 0]
        if {$keyword eq "subtype"} {
            lassign [subtype_indication c {{;} eof} 1] subtype constraint mark resolution form
            dict set item subtype_span $subtype
            dict set item constraint_span $constraint
            dict set item type_mark_span $mark
            dict set item resolution_span $resolution
            dict set item resolution_kind $form
        } elseif {$category in {units record protected protected_body} || [kind c] in {access file}} {
            set form [kind c]
            if {$category in {record protected protected_body}} {set form $category}
            if {$category eq "units"} {
                if {$form ne "range"} {reject c EXPECTED_RANGE}
                set form physical
                dict set item range_keyword_span [span c]
            }
            dict set item kind $form
            dict set item status recognized-but-unsupported
            if {$form eq "protected_body" && $ownerKind eq "package"} {
                dict set item diagnostics [list [at TYPE_PROTECTED_BODY_OUT_OF_SCOPE [span c]]]
            }
            set c(i) $c(typeDefinitionFence)
        } else {
            switch -- [kind c] {
                array {
                    dict set item kind array
                    array_definition c item
                }
                ( {
                    dict set item kind enumeration
                    enumeration c item
                }
                range {
                    dict set item kind scalar_range
                    dict set item range_keyword_span [take c]
                    set rangeStart [lindex [span c] 0]
                    lassign [range_payload c {{;} eof}] left direction directionSpan right attribute
                    dict set item range_payload_span [extent c $rangeStart]
                    dict set item range_span [extent c [lindex [dict get $item range_keyword_span] 0]]
                    dict set item left_bound_span $left
                    dict set item direction $direction
                    dict set item direction_span $directionSpan
                    dict set item right_bound_span $right
                    dict set item range_attribute_span $attribute
                }
                default {reject c EXPECTED_TYPE_DEFINITION}
            }
        }
        dict set item definition_span [extent c $definition]
    }
    if {[kind c] eq "eof"} {reject c MISSING_SEMICOLON}
    dict set item terminator_span [require c {;} UNEXPECTED_TAIL]
    if {[kind c] ne "eof"} {reject c UNEXPECTED_TAIL}
}

proc ::vhdl_index::type_declaration::at {code region} {
    return [dict create code $code severity error phase type span $region]
}

proc ::vhdl_index::type_declaration::index {state ownerKind owner first region category cause} {
    upvar 1 $state c
    set c(grammarFence) $c(i)
    set c(grammarDomain) TYPE
    set c(grammarPrefixes) {}
    set c(grammarNamePrefix) 0
    set c(typeDefinitionFence) $c(i)
    if {[peek c -1] eq ";"} {incr c(typeDefinitionFence) -1}
    set c(i) $first
    set keyword [kind c]
    set item [dict create owner_id $owner kind $keyword span $region name_span {} header_span {} \
        terminator_span {} status parsed diagnostics {}]
    if {$category eq "uncertain_opaque_item" || $cause ne {}} {
        set intro [take c]
        dict set item keyword_span $intro
        if {[is_name [kind c] 0]} {
            dict set item name_span [take c]
            if {[kind c] eq "is"} {dict set item is_span [take c]}
            dict set item header_span [extent c [lindex $intro 0]]
        }
        set issue [at TYPE_UNPROVEN_DECLARATION_BOUNDARY $region]
        if {$category eq "uncertain_opaque_item"} {
            dict set issue related_span $c(opaqueBoundary)
            dict set issue cause OBJECT_OPAQUE_BOUNDARY
        } else {
            dict set issue related_span [dict get $cause span]
            dict set issue cause [dict get $cause code]
        }
        dict set item status unrecognized
        dict set item diagnostics [list $issue]
    } else {
        if {[catch {syntax c $ownerKind $category item} issue options]} {
            if {[dict get $options -errorcode] ne {VHDL_INDEX TYPE}} {
                return -options $options $issue
            }
            dict set issue phase type
            dict lappend item diagnostics $issue
            if {$c(typeDefinitionFence) < $c(grammarFence)} {
                set c(i) $c(typeDefinitionFence)
                dict set item terminator_span [span c]
            }
        }
    }
    set c(i) $c(grammarFence)
    dict lappend item diagnostics {*}[lexical_diagnostics c $region typeLexicalAt]
    foreach issue [dict get $item diagnostics] {
        set next malformed
        if {[string match EDITION_* [dict get $issue code]]} {set next recognized-but-unsupported}
        dict set item status [combine [dict get $item status] $next]
        lappend c(typeDiagnostics) $issue
    }
    return $item
}
