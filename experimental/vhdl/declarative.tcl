# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::declarative {
    namespace path {::vhdl_index::grammar ::vhdl_index::parser}
}

proc ::vhdl_index::declarative::name_fields {state recordVar spanKey {allowTrailingSignature 0}} {
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
                if {[kind c] ne "'"} {
                    if {!$allowTrailingSignature} {reject c UNEXPECTED_SIGNATURE}
                    break
                }
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
    dict set item $spanKey $nameExtent
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
    return [name_fields c item aliased_name_span 1]
}

proc ::vhdl_index::declarative::attribute_declaration {state ownerKind recordVar} {
    upvar 1 $state c $recordVar item
    dict set item name_span [name_span c]
    if {[kind c] eq ":"} {
        dict set item kind attribute_declaration
        dict set item colon_span [take c]
        dict set item type_mark_span [selected_name c 0 1]
        if {$ownerKind in {protected configuration}} {reject c DECLARATION_OUT_OF_CONTEXT}
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
    lassign [entity_class c] class classSpan
    dict set item entity_class $class
    dict set item entity_class_span $classSpan
    dict set item is_span [require c is EXPECTED_IS]
    dict set item value_span [payload c {eof}]
    return parsed
}

proc ::vhdl_index::declarative::file_object {state recordVar} {
    upvar 1 $state c $recordVar item
    lassign [identifier_list c] names commas colon
    dict set item names $names
    dict set item comma_spans $commas
    dict set item colon_span $colon
    set item [dict merge $item [subtype_fields c {open is eof}]]
    if {[kind c] eq "open"} {
        dict set item open_span [take c]
        dict set item open_kind_span [payload c {is eof}]
        dict set item is_span [require c is EXPECTED_IS]
    } elseif {[kind c] eq "is"} {
        dict set item is_span [take c]
    }
    if {[dict exists $item is_span]} {
        if {[kind c] in {in out}} {reject c LEGACY_FILE_MODE}
        dict set item logical_name_span [payload c {eof}]
    }
}

proc ::vhdl_index::declarative::group_declaration {state ownerKind recordVar} {
    upvar 1 $state c $recordVar item
    dict set item name_span [name_span c]
    set form [kind c]
    if {$form eq "is"} {
        dict set item kind group_template
        dict set item is_span [take c]
    } else {
        dict set item kind group
        dict set item colon_span [require c : EXPECTED_COLON]
        dict set item template_span [selected_name c]
    }
    dict set item open_span [require c ( EXPECTED_OPEN]
    set rows {}
    set commas {}
    set status parsed
    while {1} {
        if {$form eq "is"} {
            lassign [entity_class c] class classSpan
            set entry [dict create entity_class $class entity_class_span $classSpan]
            if {[kind c] eq "<>"} {
                dict set entry box_span [take c]
                if {[kind c] ne ")"} {reject c BOX_MUST_BE_LAST}
            }
            dict set entry span [extent c [lindex $classSpan 0]]
        } elseif {[kind c] eq "character"} {
            set entry [dict create kind character span [take c]]
        } else {
            set entry [dict create kind name]
            set status [combine $status [name_fields c entry span]]
            if {[dict exists $entry diagnostics]} {dict lappend item diagnostics {*}[dict get $entry diagnostics]}
        }
        lappend rows $entry
        if {[kind c] ne ","} {break}
        lappend commas [take c]
    }
    dict set item members $rows
    dict set item comma_spans $commas
    dict set item close_span [require c ) EXPECTED_CLOSE]
    if {$form eq "is" && $ownerKind eq "configuration"} {reject c TEMPLATE_OUT_OF_CONTEXT}
    return $status
}

# A list selector owns its commas. Parenthesized signal-name suffixes remain
# part of that name, while instance labels are simple identifiers.
proc ::vhdl_index::declarative::selector {state recordVar {signals 0}} {
    upvar 1 $state c $recordVar item
    set start [lindex [span c] 0]
    set listKind [kind c]
    set names {}
    set commas {}
    set status parsed
    if {$listKind in {all others}} {
        take c
    } else {
        set listKind names
        while {1} {
            if {$signals} {
                set entry {}
                set status [combine $status [name_fields c entry span]]
                if {[dict exists $entry diagnostics]} {
                    dict lappend item diagnostics {*}[dict get $entry diagnostics]
                }
            } else {
                set entry [dict create span [name_span c]]
            }
            lappend names $entry
            if {[kind c] ne ","} {break}
            lappend commas [take c]
        }
    }
    dict set item selector_kind $listKind
    dict set item selector_span [extent c $start]
    dict set item selected_names $names
    dict set item comma_spans $commas
    dict set item colon_span [require c : EXPECTED_COLON]
    return $status
}

proc ::vhdl_index::declarative::disconnect {state ownerKind recordVar} {
    upvar 1 $state c $recordVar item
    set start [lindex [span c] 0]
    set status [selector c item 1]
    dict set item type_mark_span [selected_name c 0 1]
    dict set item guarded_signal_span [extent c $start]
    dict set item after_span [require c after EXPECTED_AFTER]
    dict set item time_span [payload c {eof}]
    if {$ownerKind ni {architecture entity package block generate}} {reject c OUT_OF_CONTEXT}
    return $status
}

proc ::vhdl_index::declarative::map_aspect {state form} {
    upvar 1 $state c
    set keyword [require c $form EXPECTED_MAP_KEYWORD]
    set map [require c map EXPECTED_MAP]
    if {[kind c] ne "("} {reject c EXPECTED_MAP_OPEN}
    set associations [group c]
    return [dict create keyword_span $keyword map_span $map association_span $associations \
        span [extent c [lindex $keyword 0]]]
}

proc ::vhdl_index::declarative::component_specification {state ownerKind recordVar} {
    upvar 1 $state c $recordVar item
    set start [lindex [span c] 0]
    selector c item
    dict set item component_name_span [selected_name c]
    dict set item component_specification_span [extent c $start]
    set first $c(i)
    set start [lindex [span c] 0]
    set binding {}
    if {[kind c] eq "use"} {
        dict set binding use_span [take c]
        set aspect [kind c]
        if {$aspect ni {entity configuration open}} {reject c EXPECTED_ENTITY_ASPECT}
        set aspectKeyword [take c]
        dict set binding aspect_kind $aspect
        dict set binding aspect_keyword_span $aspectKeyword
        if {$aspect ne "open"} {
            dict set binding target_span [selected_name c]
        }
        if {$aspect eq "entity" && [kind c] eq "("} {
            dict set binding architecture_open_span [take c]
            dict set binding architecture_name_span [name_span c]
            dict set binding architecture_close_span [require c ) EXPECTED_ARCHITECTURE_CLOSE]
        }
        dict set binding aspect_span [extent c [lindex $aspectKeyword 0]]
    }
    foreach form {generic port} {
        if {[kind c] eq $form} {dict set binding ${form}_map [map_aspect c $form]}
    }
    if {$c(i) != $first} {dict set binding span [extent c $start]}
    dict set item binding $binding
    if {$ownerKind ni {architecture block generate}} {reject c OUT_OF_CONTEXT}
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
    set forms {}
    switch -- $family {
        group {set forms [candidate_forms c {is group_template : group}]}
        attribute {set forms [candidate_forms c {: attribute_declaration of attribute_specification}]}
    }
    if {[llength $forms] == 1} {dict set item kind [lindex $forms 0]}
    set status parsed
    if {$uncertainty eq {}} {
        if {[catch {
            switch -- $family {
                alias {set status [alias_declaration c item]}
                attribute {set status [attribute_declaration c $ownerKind item]}
                file_object {file_object c item}
                group {set status [group_declaration c $ownerKind item]}
                disconnect {set status [disconnect c $ownerKind item]}
                configuration_specification {component_specification c $ownerKind item}
                local_use {
                    lassign [context_names c use] names commas
                    dict set item names $names
                    dict set item comma_spans $commas
                }
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
    if {$forms ne {} && $status ne "parsed"} {
        set capabilities {}
        foreach form $forms {
            set capability [::vhdl_index::declaration_capability $form]
            if {$capability ni $capabilities} {lappend capabilities $capability}
        }
        dict set item candidate_forms $forms
        dict set item candidate_capabilities $capabilities
    }
    return $item
}

# Collect local interface sites with the structural cursor. The interface
# grammar owns clause syntax and never gets an entity's site accumulator.
proc ::vhdl_index::declarative::component {state depth owner ownerKind} {
    upvar 1 $state c
    set keyword [take c]
    set start [lindex $keyword 0]
    set name {}
    if {[is_name [peek c] 0]} {set name [read_name c]}
    set is {}
    if {[peek c] eq "is"} {set is [take c]}
    descend c $depth
    set sites {}
    while {[peek c] ne "end"} {
        set first $c(i)
        set form [peek c]
        if {$form in {generic port}} {
            incr c(i)
        } elseif {[::vhdl_index::grammar::declaration_family $form] ne {}} {
            fail c UNPROVEN_COMPONENT_END [list found $form]
        }
        set marker [boundary c {{;} generic port end begin} indexed_item]
        if {$marker in {begin declaration} || $c(opaqueBoundary) ne {}} {
            fail c UNPROVEN_COMPONENT_END [list found [peek c]]
        }
        if {$marker eq ";"} {incr c(i)}
        if {$c(i) <= $first} {fail c UNPROVEN_COMPONENT_END}
        lappend sites [list $first $c(i) 1 {}]
    }
    set endOrdinal $c(i)
    set before [llength $c(diagnostics)]
    set close [terminator c component $name 1 0 1]
    set region [list $start [lindex $close 1]]
    set tail {}
    if {[peek c -1] eq ";"} {set tail [span c previous]}
    set closingName {}
    if {$c(i) - $endOrdinal > 2 + ($tail ne {})} {
        set saved $c(i)
        set c(i) [expr {$endOrdinal + 2}]
        set closingName [span c]
        set c(i) $saved
    }
    set row [dict create owner_id $owner kind component keyword_span $keyword name_span [lindex $name 1] \
        is_span $is span $region component_terminator_span $close end_name_span $closingName \
        terminator_span $tail clauses {} status parsed diagnostics {}]
    if {[llength $c(diagnostics)] != $before} {
        set cause [lindex $c(diagnostics) end]
        ::vhdl_index::ownership::withdraw_component c $region $cause $owner
        dict set row diagnostics [list [::vhdl_index::ownership::unproven_scope COMPONENT $region $cause]]
        dict set row status unrecognized
    } else {
        set result [::vhdl_index::interface::index_owner c $row $sites componentLexicalAt]
        foreach key {clauses status diagnostics} {dict set row $key [dict get $result $key]}
    }
    if {$name eq {}} {
        dict lappend row diagnostics [diagnostic c COMPONENT_EXPECTED_NAME [list span $keyword]]
        dict set row status [combine [dict get $row status] malformed]
    }
    if {$tail eq {}} {
        dict lappend row diagnostics [diagnostic c COMPONENT_MISSING_SEMICOLON {}]
        dict set row status [combine [dict get $row status] malformed]
    }
    if {$ownerKind ni {architecture package block generate}} {
        dict lappend row diagnostics [diagnostic c COMPONENT_OUT_OF_CONTEXT [list span $keyword]]
        dict set row status [combine [dict get $row status] malformed]
    }
    return $row
}
