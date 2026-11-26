# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::declarative {
    namespace path {::vhdl_index::grammar ::vhdl_index::parser}
}

proc ::vhdl_index::declarative::alias_name {state recordVar} {
    upvar 1 $state c $recordVar item
    set start [lindex [span c] 0]
    set groups {}
    set embedded {}
    set trailing {}
    set status parsed
    if {[kind c] eq "<<"} {
        if {$c(edition) < 2008} {reject c EDITION_EXTERNAL_NAME}
        group c
        set status recognized-but-unsupported
        dict set item name_form external
    } else {
        if {[kind c] eq "character"} {reject c EXPECTED_NAME}
        designator c
    }
    while {1} {
        switch -- [kind c] {
            . {
                take c
                if {[kind c] eq "all"} {take c} else {designator c}
            }
            ( {lappend groups [group c]}
            {[} {
                set nameExtent [extent c $start]
                set trailing [signature c]
                if {[kind c] ne "'"} {break}
                lappend embedded $trailing
                set trailing {}
            }
            ' {
                take c
                if {[kind c] eq "range" || ([kind c] eq "subtype" && $c(edition) >= 2008)} {
                    take c
                } else {
                    name_span c
                }
            }
            default {break}
        }
    }
    if {$trailing eq {}} {set nameExtent [extent c $start]}
    dict set item aliased_name_span $nameExtent
    if {$groups ne {}} {dict set item name_payload_spans $groups}
    if {$embedded ne {}} {dict set item embedded_signatures $embedded}
    if {$trailing ne {}} {dict set item signature $trailing}
    if {$status ne "parsed"} {
        dict lappend item diagnostics [problem c UNSUPPORTED_EXTERNAL_NAME [list span $nameExtent]]
    }
    return $status
}

proc ::vhdl_index::declarative::subtype_fields {state stops} {
    upvar 1 $state c
    lassign [subtype_indication c $stops 1 1] extent constraint mark resolution resolutionKind
    return [dict create subtype_span $extent type_mark_span $mark constraint_span $constraint \
        resolution_span $resolution resolution_kind $resolutionKind]
}

proc ::vhdl_index::declarative::alias_declaration {state recordVar} {
    upvar 1 $state c $recordVar item
    lassign [designator c] designator form
    dict set item name_span $designator
    dict set item designator_kind $form
    if {[kind c] eq ":"} {
        dict set item colon_span [take c]
        set item [dict merge $item [subtype_fields c {is eof}]]
    }
    dict set item is_span [require c is EXPECTED_IS]
    return [alias_name c item]
}

proc ::vhdl_index::declarative::attribute_declaration {state ownerKind recordVar} {
    upvar 1 $state c $recordVar item
    dict set item name_span [name_span c]
    if {[kind c] eq ":"} {
        dict set item kind attribute_declaration
        dict set item colon_span [take c]
        dict set item type_mark_span [selected_name c 0 1]
        if {$ownerKind eq "protected"} {reject c DECLARATION_OUT_OF_CONTEXT}
        return parsed
    }

    dict set item kind attribute_specification
    dict set item of_span [require c of EXPECTED_OF]
    set start [lindex [span c] 0]
    set names {}
    set commas {}
    set listForm [kind c]
    if {$listForm in {all others}} {
        dict set item selector_span [take c]
    } else {
        set listForm names
        while {1} {
            lassign [designator c] extent form
            set name [dict create name_span $extent designator_kind $form]
            if {[kind c] eq "\["} {dict set name signature [signature c]}
            lappend names $name
            if {[kind c] ne ","} {break}
            lappend commas [take c]
        }
    }
    dict set item entity_list_kind $listForm
    dict set item entity_list_span [extent c $start]
    dict set item entities $names
    dict set item comma_spans $commas
    dict set item entity_class_colon_span [require c : EXPECTED_ENTITY_CLASS_COLON]
    set class [kind c]
    if {$class ni {entity architecture configuration procedure function package type subtype
        constant signal variable component label literal units group file property sequence}} {
        reject c EXPECTED_ENTITY_CLASS
    }
    if {$class in {property sequence} && $c(edition) < 2008} {reject c EDITION_ATTRIBUTE_ENTITY_CLASS}
    dict set item entity_class $class
    dict set item entity_class_span [take c]
    dict set item is_span [require c is EXPECTED_IS]
    dict set item value_span [payload c {eof}]
    return parsed
}

# The structural walk owns the fence. Grammar recovery cannot consume a sibling.
proc ::vhdl_index::declarative::index {state owner ownerKind family first fence terminator uncertainty} {
    upvar 1 $state c
    set resume $c(i)
    set c(i) $first
    set c(grammarFence) $fence
    set c(grammarDomain) [string toupper $family]
    set c(grammarPrefixes) {}
    set c(grammarNamePrefix) 0
    set keyword [take c]
    set start [lindex $keyword 0]
    set item [dict create owner_id $owner kind $family keyword_span $keyword terminator_span $terminator \
        diagnostics {}]
    set status parsed
    if {$uncertainty eq {}} {
        if {[catch {
            switch -- $family {
                alias {set status [alias_declaration c item]}
                attribute {set status [attribute_declaration c $ownerKind item]}
            }
            if {[kind c] ne "eof"} {reject c UNEXPECTED_TAIL [list found [kind c]]}
        } issue options]} {
            if {[dict get $options -errorcode] ne [list VHDL_INDEX $c(grammarDomain)]} {
                return -options $options $issue
            }
            dict lappend item diagnostics $issue
            set status [expr {[string match EDITION_* [dict get $issue code]] ?
                "recognized-but-unsupported" : "malformed"}]
        }
    } else {
        dict lappend item diagnostics [problem c UNPROVEN_BOUNDARY [list related_span $uncertainty]]
        set status unrecognized
    }
    set c(i) $fence
    if {$terminator eq {}} {
        dict lappend item diagnostics [problem c MISSING_SEMICOLON]
        set status [combine $status malformed]
        set region [extent c $start]
    } else {
        set region [list $start [lindex $terminator 1]]
    }
    set c(i) $resume
    set lexical [lexical_diagnostics c $region declarativeLexicalAt]
    if {$lexical ne {}} {
        dict lappend item diagnostics {*}$lexical
        set status [combine $status malformed]
    }
    dict set item span $region
    dict set item status $status
    return $item
}
