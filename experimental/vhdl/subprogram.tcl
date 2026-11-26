# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::subprogram {
    namespace path {::vhdl_index::grammar ::vhdl_index::parser}
}

proc ::vhdl_index::subprogram::generic_map {state} {
    upvar 1 $state c
    set start [lindex [require c generic EXPECTED_GENERIC] 0]
    require c map EXPECTED_MAP
    return [list [group c] [extent c $start]]
}

# Both callers own the separator. A formal's IS default belongs to its
# interface item; an ordinary specification's IS is fenced by the walker.
proc ::vhdl_index::subprogram::specification {state recordVar context} {
    upvar 1 $state c $recordVar item
    set purity {}
    set puritySpan {}
    if {[kind c] in {pure impure}} {
        set purity [kind c]
        set puritySpan [take c]
        if {[kind c] ne "function"} {reject c EXPECTED_FUNCTION}
    }
    set form [kind c]
    if {$form ni {function procedure}} {reject c EXPECTED_KIND}
    set keyword [take c]
    dict set item subprogram_kind $form
    dict set item explicit_purity $purity
    dict set item purity_span $puritySpan
    if {$form eq "function"} {
        dict set item effective_purity [expr {$purity eq {} ? "pure" : $purity}]
    }
    set nameKind [kind c]
    set name [name_span c [expr {$form eq "function"}]]
    if {$context eq "formal"} {
        dict set item names [list $name]
    } else {
        dict set item keyword_span $keyword
        dict set item designator_span $name
        dict set item designator_kind [expr {$nameKind eq "string" ? "operator" : $nameKind}]
        if {$context eq "instantiation"} {
            if {$purity ne {} || $nameKind eq "string"} {reject c INVALID_INSTANTIATION_DESIGNATOR}
            return [list parsed {}]
        }
    }

    if {$nameKind eq "string"} {validate_operator c $name}

    set status parsed
    set diagnostics {}
    if {$context eq "ordinary" && [kind c] eq "generic"} {
        if {$c(edition) < 2008} {reject c EDITION_SUBPROGRAM_GENERIC_HEADER}
        dict set item generic_keyword_span [take c]
        set generics [::vhdl_index::interface::list_body c generic]
        dict set item generic_parameters $generics
        set status [dict get $generics status]
        lappend diagnostics {*}[dict get $generics diagnostics]
        if {[kind c] eq "generic"} {
            lassign [generic_map c] group map
            dict set item generic_map_span $map
            dict set item generic_map_group_span $group
        }
    }
    set parameterKeyword {}
    if {[kind c] eq "parameter"} {set parameterKeyword [take c]}
    if {[kind c] eq "(" || $parameterKeyword ne {}} {
        dict set item parameter_keyword_span $parameterKeyword
        set params [::vhdl_index::interface::list_body c parameter $form [expr {$context eq "ordinary"}]]
        dict set item parameters $params
        set status [combine $status [dict get $params status]]
        lappend diagnostics {*}[dict get $params diagnostics]
    }
    if {$form eq "function"} {
        dict set item return_keyword_span [require c return EXPECTED_RETURN]
        dict set item return_type_span [selected_name c 0 1]
    }
    return [list $status $diagnostics]
}

proc ::vhdl_index::subprogram::instantiation {state recordVar} {
    upvar 1 $state c $recordVar item
    dict set item is_span [require c is EXPECTED_IS]
    dict set item new_span [require c new EXPECTED_NEW]
    dict set item target_span [selected_name c 1]
    if {[kind c] eq "\["} {dict set item signature_span [group c]}
    if {[kind c] eq "generic"} {
        lassign [generic_map c] group map
        dict set item generic_map_span $map
        dict set item generic_map_group_span $group
    }
}

proc ::vhdl_index::subprogram::index {state owner first fence category {introducer {}}} {
    upvar 1 $state c
    set started [clock microseconds]
    set resume $c(i)
    set c(i) $first
    set c(grammarFence) $fence
    set c(grammarDomain) SUBPROGRAM
    set c(grammarPrefixes) $::vhdl_index::interface::classes
    set c(grammarNamePrefix) 1
    set start [lindex [span c] 0]
    set item [dict create owner_id $owner source_id [dict get $c(snapshot) id] category $category]
    set status parsed
    set issues {}
    set caught [catch {
        lassign [specification c item [expr {$category eq "instantiation" ? $category : "ordinary"}]] status issues
        if {$category eq "instantiation"} {
            dict set item specification_span [extent c $start]
            instantiation c item
            set status recognized-but-unsupported
        }
        if {[kind c] ne "eof"} {reject c UNEXPECTED_TAIL [list found [kind c]]}
    } issue options]
    if {$caught} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX SUBPROGRAM}} {
            return -options $options $issue
        }
        lappend issues $issue
        set status [expr {[string match EDITION_* [dict get $issue code]] ?
            "recognized-but-unsupported" : "malformed"}]
    }
    set c(i) $fence
    set bounded [extent c $start]
    if {![dict exists $item specification_span]} {dict set item specification_span $bounded}
    dict set item span $bounded
    if {$category eq "body"} {
        dict set item is_span $introducer
    } else {
        dict set item terminator_span $introducer
        if {$introducer eq {}} {
            lappend issues [problem c MISSING_SEMICOLON]
            set status malformed
        } else {
            dict set item span [list $start [lindex $introducer 1]]
        }
    }
    set lexical [lexical_diagnostics c [dict get $item span] subprogramLexicalAt]
    if {$lexical ne {}} {
        lappend issues {*}$lexical
        set status [combine $status malformed]
    }
    set c(i) $resume
    set diagnostics {}
    foreach issue $issues {
        if {![dict exists $issue phase]} {dict set issue phase subprogram}
        lappend diagnostics $issue
    }
    dict set item status $status
    dict set item diagnostics $diagnostics
    incr c(subprogramTime) [expr {[clock microseconds] - $started}]
    return $item
}
