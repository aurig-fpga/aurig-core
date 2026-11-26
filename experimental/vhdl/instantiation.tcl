# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc ::vhdl_index::parser::parse_instance {state owner ownerKind opening label colon category starter target components targetIssue postponed} {
    upvar 1 $state c
    set code [catch {
        instance_statement c $ownerKind $opening $label $colon $category $starter $target $components $targetIssue $postponed
    } row options]
    if {$code} {
        if {[dict get $options -errorcode] ni {{VHDL_INDEX STRUCTURE} {VHDL_INDEX INSTANTIATION}} ||
            [string match *LIMIT [dict get $row code]]} {
            if {[dict get $options -errorcode] eq {VHDL_INDEX INSTANTIATION}} {
                return -code error -errorcode {VHDL_INDEX STRUCTURE} $row
            }
            return -options $options $row
        }
        # A following label or structural ending fences this failure.
        # The opaque walker refuses to skip a possible nested owner.
        set marker [peek c]
        if {$marker ni {end elsif else when process assert} &&
            $marker ni {postponed with block} && ![statement_label c]} {
            opaque_concurrent c $ownerKind
        }
        concurrent_candidate c $owner $opening malformed $row [list ${category}_instantiation] \
            {instantiations map_associations}
    } elseif {[dict get $row status] eq "malformed"} {
        concurrent_candidate c $owner $opening malformed [lindex [dict get $row diagnostics] 0] \
            [list ${category}_instantiation] {instantiations map_associations}
    } else {
        dict set row owner_id $owner
        lappend c(instantiations) $row
    }
}

proc ::vhdl_index::parser::instance_statement {state ownerKind opening label colon category starter target components targetIssue postponed} {
    upvar 1 $state c
    set keyword {}
    if {$starter in {entity component configuration}} {set keyword [take c]}
    if {$targetIssue ne {}} {return -code error -errorcode {VHDL_INDEX INSTANTIATION} $targetIssue}
    if {$target eq {}} {set target [::vhdl_index::grammar::selected_name c 0 0 components]}
    set selector {}
    if {$category eq "entity" && [peek c] eq "("} {
        set open [take c]
        set name [::vhdl_index::grammar::name_span c]
        set close [::vhdl_index::grammar::require c ) EXPECTED_ARCHITECTURE_CLOSE]
        set selector [dict create span [list [lindex $open 0] [lindex $close 1]] \
            open_span $open name_span $name close_span $close]
    }
    set maps {}
    set issue {}
    if {$label eq {}} {
        set issue [diagnostic c MISSING_INSTANTIATION_LABEL [list span $target]]
    } elseif {$postponed ne {}} {
        set issue [diagnostic c POSTPONED_INSTANTIATION [list span $postponed]]
    } elseif {$ownerKind eq "entity"} {
        set issue [diagnostic c INSTANTIATION_OUT_OF_CONTEXT [list span $target]]
    }
    while {[set form [peek c]] in {generic port}} {
        if {$issue eq {} && ([dict exists $maps $form] || ($form eq "generic" && [dict exists $maps port]))} {
            set issue [diagnostic c INSTANTIATION_MAP_ORDER [list found $form]]
        }
        dict set maps $form [map_aspect c $form concurrent_instantiation]
    }
    if {[peek c] ne ";"} {fail c EXPECTED_INSTANTIATION_SEMICOLON}
    set tail [take c]
    set region [list $opening [lindex $tail 1]]
    if {$issue ne {}} {
        return [dict create span $region status malformed diagnostics [list $issue]]
    }
    set lexical [::vhdl_index::grammar::association_lexical c $region]
    foreach diagnostic $lexical {
        # Map diagnostics are covered independently of the occurrence skeleton.
        set at [lindex [dict get $diagnostic span] 0]
        set inside 0
        dict for {form map} $maps {
            lassign [dict get $map association_span] start end
            if {$at >= $start && $at < $end} {set inside 1}
        }
        if {!$inside} {return [dict create span $region status malformed diagnostics [list $diagnostic]]}
    }
    return [dict create span $region label [lindex $label 0] label_span [lindex $label 1] colon_span $colon \
        category $category keyword_span $keyword target_span $target target_components $components \
        architecture_selector $selector maps $maps terminator_span $tail status parsed diagnostics {}]
}

proc ::vhdl_index::parser::statement_label {state} {
    upvar 1 $state c
    return [expr {[is_name [peek c] 0] && [peek c 1] eq ":"}]
}
