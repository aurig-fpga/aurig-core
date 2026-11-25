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

proc ::vhdl_index::type_declaration::bounded_subtype {state stops {subtypeKey subtype_span}} {
    upvar 1 $state c
    lassign [subtype_indication c [linsert $stops end <>] 1 1] subtype constraint mark resolution form
    return [dict create $subtypeKey $subtype type_mark_span $mark constraint_span $constraint \
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
    set item [dict merge $item [bounded_subtype c {{;} eof}]]
}

proc ::vhdl_index::type_declaration::record_field {state fieldVar} {
    upvar 1 $state c $fieldVar field
    lassign [identifier_list c] names separators colon
    dict set field names $names
    dict set field separator_spans $separators
    dict set field colon_span $colon
    if {[record_field_prefix c]} {reject c EXPECTED_NAME}
    set field [dict merge $field [bounded_subtype c {{;} eof}]]
    dict set field terminator_span [require c {;} MISSING_FIELD_SEMICOLON]
}

proc ::vhdl_index::type_declaration::record_definition {state recordVar} {
    upvar 1 $state c $recordVar item
    dict set item record_keyword_span [require c record EXPECTED_RECORD]
    set sites $c(typeMemberSites)
    unset c(typeMemberSites)
    set fence $c(grammarFence)
    set parent [lindex [dict get $item span] 0]
    set fields {}
    set c(grammarNamePrefix) record
    foreach site $sites {
        lassign $site c(i) c(grammarFence) separated
        while {$c(i) < $c(grammarFence)} {
            set start [lindex [span c] 0]
            set field [dict create record_id $parent names {} terminator_span {} status parsed diagnostics {}]
            if {[catch {record_field c field} issue options]} {
                if {[dict get $options -errorcode] ne {VHDL_INDEX TYPE}} {
                    return -options $options $issue
                }
                dict set issue phase type
                set code [dict get $issue code]
                dict lappend item diagnostics $issue
                dict set field diagnostics [list $issue]
                dict set field status [expr {[string match EDITION_* $code] ?
                    "recognized-but-unsupported" : "malformed"}]
                if {$code ne "TYPE_MISSING_FIELD_SEMICOLON" || ![record_field_prefix c]} {
                    set c(i) $c(grammarFence)
                    if {$separated} {dict set field terminator_span [span c previous]}
                }
            }
            dict set field span [extent c $start]
            lappend fields $field
        }
    }
    set c(grammarFence) $fence
    set c(grammarNamePrefix) 0
    dict set item fields $fields
    if {$fields eq {}} {reject c EXPECTED_RECORD_FIELD}
    member_terminator c record item record_terminator_span
}

proc ::vhdl_index::type_declaration::member_terminator {state keyword itemVar tailKey} {
    upvar 1 $state c $itemVar item
    set start [lindex [span c] 0]
    dict set item end_span [require c end EXPECTED_END]
    dict set item end_${keyword}_span [require c $keyword EXPECTED_END_KIND]
    if {[is_name [kind c] 0]} {dict set item end_name_span [take c]}
    set tail [extent c $start]
    if {[kind c] eq ";"} {set tail [list $start [lindex [span c] 1]]}
    dict set item $tailKey $tail
}

proc ::vhdl_index::type_declaration::range_fields {state itemVar stops} {
    upvar 1 $state c $itemVar item
    dict set item range_keyword_span [require c range EXPECTED_RANGE]
    set start [lindex [span c] 0]
    lassign [range_payload c $stops] left direction directionSpan right attribute
    dict set item range_payload_span [extent c $start]
    dict set item range_span [extent c [lindex [dict get $item range_keyword_span] 0]]
    dict set item left_bound_span $left
    dict set item direction $direction
    dict set item direction_span $directionSpan
    dict set item right_bound_span $right
    dict set item range_attribute_span $attribute
}

proc ::vhdl_index::type_declaration::physical_unit {state form rowVar} {
    upvar 1 $state c $rowVar row
    dict set row name_span [name_span c]
    if {$form eq "secondary"} {
        dict set row assignment_span [require c = EXPECTED_UNIT_ASSIGNMENT]
        set first [lindex [span c] 0]
        if {[kind c] eq "number"} {
            set magnitude [take c]
            dict set row magnitude_span $magnitude
            # The lexer recognizes abstract literals. A secondary unit
            # specifically requires the integer spelling of a magnitude.
            if {[regexp -nocase {\.|e-} [::vhdl_index::slice $c(snapshot) $magnitude]]} {
                return -code error -errorcode {VHDL_INDEX TYPE} [at TYPE_EXPECTED_INTEGER_MAGNITUDE $magnitude]
            }
        }
        if {[is_name [kind c] 0] && [kind c 1] eq "="} {reject c EXPECTED_UNIT_REFERENCE}
        dict set row unit_reference_span [selected_name c]
        dict set row literal_span [extent c $first]
    }
    dict set row terminator_span [require c {;} MISSING_UNIT_SEMICOLON]
}

proc ::vhdl_index::type_declaration::physical_definition {state itemVar} {
    upvar 1 $state c $itemVar item
    set sites $c(typeMemberSites)
    unset c(typeMemberSites)
    range_fields c item {units <> eof}
    dict set item units_keyword_span [require c units EXPECTED_UNITS]
    set fence $c(grammarFence)
    set parent [lindex [dict get $item span] 0]
    set primary {}
    set secondary {}
    # A unit consumes its semicolon, leaves a proved secondary prefix
    # after consuming a partial member, or advances to the physical fence.
    foreach site $sites {
        lassign $site c(i) c(grammarFence) separated
        while {$c(i) < $c(grammarFence)} {
            set start [lindex [span c] 0]
            set form [expr {$primary eq {} ? "primary" : "secondary"}]
            set row [dict create type_id $parent kind $form name_span {} terminator_span {} status parsed diagnostics {}]
            if {[catch {physical_unit c $form row} issue options]} {
                if {[dict get $options -errorcode] ne {VHDL_INDEX TYPE}} {
                    return -options $options $issue
                }
                dict set issue phase type
                dict lappend item diagnostics $issue
                dict set row diagnostics [list $issue]
                dict set row status malformed
                if {[dict get $issue code] ni {TYPE_MISSING_UNIT_SEMICOLON TYPE_EXPECTED_UNIT_REFERENCE} ||
                    ![is_name [kind c] 0] || [kind c 1] ne "="} {
                    set c(i) $c(grammarFence)
                    if {$separated} {dict set row terminator_span [span c previous]}
                }
            }
            dict set row span [extent c $start]
            if {$form eq "primary"} {
                set primary $row
            } else {
                lappend secondary $row
            }
        }
    }
    set c(grammarFence) $fence
    if {$primary eq {}} {reject c EXPECTED_PRIMARY_UNIT}
    dict set item primary_unit $primary
    dict set item secondary_units $secondary
    member_terminator c units item physical_terminator_span
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
        } elseif {$category eq "units"} {
            dict set item kind physical
            physical_definition c item
        } elseif {$category in {protected protected_body}} {
            dict set item kind $category
            dict set item status recognized-but-unsupported
            if {$category eq "protected_body" && $ownerKind eq "package"} {
                dict set item diagnostics [list [at TYPE_PROTECTED_BODY_OUT_OF_SCOPE [span c]]]
            }
            set c(i) $c(typeDefinitionFence)
        } else {
            switch -- [kind c] {
                access {
                    dict set item kind access
                    dict set item access_keyword_span [take c]
                    set item [dict merge $item [bounded_subtype c {{;} eof} designated_subtype_span]]
                }
                file {
                    dict set item kind file
                    dict set item file_keyword_span [take c]
                    dict set item of_span [require c of EXPECTED_FILE_OF]
                    dict set item type_mark_span [selected_name c 0 1]
                }
                array {
                    dict set item kind array
                    array_definition c item
                }
                record {
                    dict set item kind record
                    record_definition c item
                }
                ( {
                    dict set item kind enumeration
                    enumeration c item
                }
                range {
                    dict set item kind scalar_range
                    range_fields c item {{;} eof}
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
            if {[kind c] in {array record access file}} {dict set item kind [kind c]}
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
