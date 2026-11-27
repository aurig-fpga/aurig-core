# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Explicit opt-in after frontend.tcl. Structural analysis never loads this.
if {[info commands ::vhdl_index::bounded::parse] eq {}} {
    source [file join [file dirname [info script]] bounded.tcl]
}
source [file join [file dirname [info script]] payload_sites.tcl]

namespace eval ::vhdl_index::payload {
    variable batchLimits {selections 64 rows 16384 parses 8192 tokens 262144 diagnostics 4096}
    variable projectionLimit 256
    variable families {
        entity_interfaces package_interfaces block_interfaces component_interfaces formal_parameters record_fields
        subprogram_specifications object_declarations type_declarations attribute_declarations
        file_objects disconnect_specifications generate_parameters
        concurrent_assertions concurrent_signal_assignments sequential_assertions report_statements
        wait_statements return_statements next_statements exit_statements variable_assignments
        sequential_signal_assignments control_flow_envelopes loop_parameters
    }
}

proc ::vhdl_index::payload::field {row key {fallback {}}} {
    if {[dict exists $row $key]} {return [dict get $row $key]}
    return $fallback
}

proc ::vhdl_index::payload::qualified_result {view} {
    set result [dict get $view result]
    set sourceId [dict get $view source_id]
    set tapeIdentity [list $sourceId [dict get $result edition] [dict get $result limits tokens]]
    if {[dict get $result source_id] ne $sourceId ||
        [dict get $result snapshot id] ne $sourceId ||
        [field [dict get $result tape] provenance] ne $tapeIdentity} {
        return -code error -errorcode {VHDL_INDEX PAYLOAD_PROVENANCE} \
            "Expected a view, snapshot and token tape from the same analysis, edition and token budget"
    }
    return $result
}

proc ::vhdl_index::payload::owner_address {view id} {
    set address [::vhdl_index::regions::address $view $id]
    if {![dict exists $view rows $address]} {
        return -code error -errorcode {VHDL_INDEX PAYLOAD_OWNER} "Unknown payload owner"
    }
    return $address
}

proc ::vhdl_index::payload::new_collection {view result {wanted {}} {cap 0}} {
    return [dict create view $view result $result wanted $wanted cap $cap \
        known 0 proved 0 rows {} evidence {} incomplete 0 duplicate_visits 0]
}

proc ::vhdl_index::payload::interested {collection occurrence} {
    upvar 1 $collection state
    set wanted [dict get $state wanted]
    if {$wanted ne {} && $wanted ne $occurrence} {return 0}
    if {$wanted ne {}} {dict set state known 1}
    return 1
}

proc ::vhdl_index::payload::slot {collection occurrence role entry carrier key requirement {marker {}}} {
    upvar 1 $collection state
    if {![interested state $occurrence]} {return}
    set status [field $carrier status parsed]
    set extent [field $carrier $key]
    set presence present
    if {$status ne "parsed" || ($extent eq {} && ($requirement eq "required" ||
        ($marker ne {} && [field $carrier $marker] ne {})))} {
        set presence unavailable
        dict set state incomplete 1
    } elseif {$extent eq {}} {
        set presence absent
    } elseif {$entry eq {}} {
        set presence atomic
    }
    set view [dict get $state view]
    set occurrenceId [::vhdl_index::regions::identity $view $occurrence]
    set id [list $occurrenceId $role]
    if {[dict exists $state rows $id]} {return}
    set cap [dict get $state cap]
    if {$cap && [dict size [dict get $state rows]] >= $cap} {
        return -code error -errorcode {VHDL_INDEX PAYLOAD_ROW_LIMIT} "Payload inventory exceeded the batch row limit"
    }
    set issues [concat [field $carrier diagnostics] [field $carrier context_diagnostics]]
    set descriptor [dict create source_id [dict get $view source_id] edition [dict get $state result edition] \
        owner_id [dict get $state owner] occurrence_id $occurrenceId role $role entry $entry span $extent \
        availability [expr {$presence eq "unavailable" ? "unavailable" : "proved"}] \
        completeness [expr {$presence eq "unavailable" ? "unavailable" : "complete"}] \
        presence $presence carrier_status $status diagnostics $issues]
    set at [lindex $extent 0]
    if {$at eq {}} {set at [lindex $occurrence 1]}
    dict set state rows $id [list $at $id $descriptor]
}

proc ::vhdl_index::payload::relevant {capabilities} {
    variable families
    foreach family $capabilities {
        if {$family in $families} {return 1}
    }
    return 0
}

proc ::vhdl_index::payload::record_evidence {collection id proof} {
    upvar 1 $collection state
    if {[dict exists $state evidence $id]} {return}
    set cap [dict get $state cap]
    if {$cap && [dict size [dict get $state evidence]] >= $cap} {
        return -code error -errorcode {VHDL_INDEX PAYLOAD_ROW_LIMIT} "Payload evidence exceeded the batch row limit"
    }
    dict set state evidence $id $proof
    dict set state incomplete 1
}

proc ::vhdl_index::payload::loss {collection address direct} {
    upvar 1 $collection state
    set view [dict get $state view]
    lassign [dict get $view rows $address] kind extent _ parent availability row
    if {![relevant [field $row capabilities]] && [lindex $address 0] ne "component"} {return 0}
    # Like scoped structural coverage, a bounded opaque child is subtree loss.
    if {$direct && $availability eq "unsupported" &&
        $kind in {package block generate configuration_block configuration_block_item}} {return 0}
    set id [::vhdl_index::regions::identity $view $address]
    record_evidence state $id [dict merge $row [dict create owner_id \
        [::vhdl_index::regions::identity $view $parent] evidence_id $id availability $availability]]
    return 1
}

proc ::vhdl_index::payload::visit {collection address} {
    upvar 1 $collection state
    set view [dict get $state view]
    lassign [dict get $view rows $address] kind extent _ parent availability row
    if {$availability ne "proved"} {
        return [loss state $address 0]
    }
    dict set state owner [::vhdl_index::regions::identity $view $address]
    set wanted [dict get $state wanted]
    if {$wanted eq {}} {
        foreach gap [field [dict get $view gaps] $address] {loss state $gap 1}
    }
    # Scope metadata supplies the canonical owner for headers. The remaining
    # carriers come directly from the existing grouped records.
    set role [lindex $address 0]
    interested state $address
    switch -- $role {
        interface - component {
            dict set state proved 1
            clauses state [dict get $row clauses]
        }
        specification {
            dict set state proved 1
            if {[dict exists $row parameters]} {interface_items state [dict get $row parameters] parameter}
            if {[dict exists $row generic_parameters]} {interface_items state [dict get $row generic_parameters] generic}
        }
        type_members {
            if {$kind eq "record"} {
                dict set state proved 1
                foreach member [candidate_rows [dict get $row fields] [lindex $wanted 1]] {
                    range_constraint state [list record_field [lindex [dict get $member span] 0]] $member
                }
            }
        }
        region {
            variable families
            foreach family $families {
                if {[::vhdl_index::regions::applicable $role $kind $family]} {
                    dict set state proved 1
                    break
                }
            }
            if {$kind in {generate_alternative if_alternative case_generate}} {dict set state proved 1}
            region_sites state $address $kind $row
        }
    }
    return 1
}

proc ::vhdl_index::payload::ordered {collection} {
    set result {}
    set pairs [lsort -index 1 [dict values [dict get $collection rows]]]
    foreach pair [lsort -integer -index 0 $pairs] {
        lappend result [lindex $pair 2]
    }
    return $result
}

# The child table exists only during this request, as in query::subtree.
proc ::vhdl_index::payload::collect {collection selections} {
    upvar 1 $collection state
    set view [dict get $state view]
    set roots {}
    set children {}
    set needsChildren 0
    foreach selection $selections {
        if {[llength $selection] != 2 || [lindex $selection 1] ni {direct subtree}} {
            return -code error -errorcode {VHDL_INDEX PAYLOAD_SELECTION} "Expected owner and direct/subtree pairs"
        }
        lassign $selection id mode
        set root [owner_address $view $id]
        dict set roots [list $root $mode] $id
        if {$mode eq "subtree"} {set needsChildren 1}
    }
    if {$needsChildren} {
        dict for {address row} [dict get $view rows] {
            set parent [lindex $row 3]
            if {$parent ne {}} {dict lappend children $parent $address}
        }
    }
    set visited {}
    set expanded {}
    set summaries {}
    dict for {key id} $roots {
        lassign $key root mode
        set pending [list $root]
        for {set i 0} {$i < [llength $pending]} {incr i} {
            set address [lindex $pending $i]
            if {$mode eq "subtree" && ![dict exists $expanded $address]} {
                dict set expanded $address 1
                lappend pending {*}[field $children $address]
            }
            if {[dict exists $visited $address]} {
                dict incr state duplicate_visits
                continue
            }
            dict set visited $address 1
            visit state $address
        }
        lappend summaries [dict create owner_id $id selection $mode \
            availability [lindex [dict get $view rows $root] 4]]
    }
    return $summaries
}

proc ::vhdl_index::payload::ordered_evidence {collection} {
    set pairs {}
    foreach id [lsort [dict keys [dict get $collection evidence]]] {
        set proof [dict get $collection evidence $id]
        lappend pairs [list [lindex [dict get $proof span] 0] $proof]
    }
    set result {}
    foreach pair [lsort -integer -index 0 $pairs] {lappend result [lindex $pair 1]}
    return $result
}

proc ::vhdl_index::payload::coverage {collection} {
    if {[dict get $collection incomplete]} {
        return [expr {[dict get $collection proved] ? "partial" : "unavailable"}]
    }
    return [expr {[dict get $collection proved] ? "complete" : "not_applicable"}]
}

proc ::vhdl_index::payload::inventory {view owner {mode direct}} {
    set state [new_collection $view [qualified_result $view]]
    set summary [lindex [collect state [list [list $owner $mode]]] 0]
    set rows [ordered $state]
    set completeness [coverage $state]
    return [dict merge $summary [dict create completeness $completeness rows $rows \
        evidence [ordered_evidence $state]]]
}

proc ::vhdl_index::payload::parse_slot {result descriptor interval limits} {
    lassign $interval first last
    return [::vhdl_index::bounded::parse [dict get $result snapshot] [dict get $result tape] \
        [dict get $descriptor edition] [dict get $descriptor entry] $first $last $limits]
}

proc ::vhdl_index::payload::select {view owner occurrence role {limits {}}} {
    set result [qualified_result $view]
    set address [owner_address $view $owner]
    set wanted [::vhdl_index::regions::address $view $occurrence]
    set state [new_collection $view $result $wanted]
    visit state $address
    if {![dict get $state known]} {
        return -code error -errorcode {VHDL_INDEX PAYLOAD_OCCURRENCE} "Unknown payload occurrence for this owner"
    }
    set answer [dict create descriptor {} status not_applicable token_interval {} token_span {} \
        unresolved {} diagnostics {} node_count 0 grammar {}]
    set id [list $occurrence $role]
    if {![dict exists $state rows $id]} {return $answer}
    set descriptor [lindex [dict get $state rows $id] 2]
    dict set answer descriptor $descriptor
    set extent [dict get $descriptor span]
    set presence [dict get $descriptor presence]
    dict set answer status $presence
    dict set answer diagnostics [dict get $descriptor diagnostics]
    if {$presence eq "unavailable" && $extent ne {}} {dict set answer unresolved [list $extent]}
    if {$presence ne "present"} {return $answer}
    set tape [dict get $result tape]
    set interval [::vhdl_index::bounded::interval $tape $extent]
    set parsed [parse_slot $result $descriptor $interval $limits]
    dict set answer status [dict get $parsed status]
    dict set answer grammar $parsed
    dict set answer token_interval $interval
    dict set answer token_span [dict get $parsed span]
    if {![dict get $parsed complete]} {dict set answer unresolved [list $extent]}
    dict set answer diagnostics [concat [dict get $answer diagnostics] [dict get $parsed diagnostics]]
    dict set answer node_count [llength [dict get $parsed rows]]
    return $answer
}

proc ::vhdl_index::payload::nodes {outcome ids} {
    variable projectionLimit
    if {[llength $ids] > $projectionLimit} {
        return -code error -errorcode {VHDL_INDEX PAYLOAD_PROJECTION_LIMIT} "Too many node projections"
    }
    set rows {}
    set parsed [dict get $outcome grammar]
    foreach id $ids {lappend rows [::vhdl_index::bounded::node $parsed $id]}
    return $rows
}

proc ::vhdl_index::payload::batch_limits {requested} {
    variable batchLimits
    set limits $batchLimits
    dict for {key value} $requested {
        if {![dict exists $limits $key] || ![string is integer -strict $value] ||
            $value < 1 || $value > [dict get $limits $key]} {
            return -code error -errorcode {VHDL_INDEX PAYLOAD_LIMIT} "Invalid batch limit $key=$value"
        }
        dict set limits $key $value
    }
    return $limits
}

# Retain each diagnostic once. Every requesting role can still reference it.
proc ::vhdl_index::payload::diagnostic_ids {registryVar countVar issues limit} {
    upvar 1 $registryVar registry $countVar references
    set ids {}
    foreach issue $issues {
        if {[dict exists $registry $issue] && [dict exists $ids [dict get $registry $issue]]} {continue}
        if {$references >= $limit} {return [list [dict keys $ids] 0]}
        if {![dict exists $registry $issue]} {
            dict set registry $issue [dict size $registry]
        }
        dict set ids [dict get $registry $issue] 1
        incr references
    }
    return [list [dict keys $ids] 1]
}

# The parser's arena goes out of scope here. Even successful work leaves only
# status, precise failure evidence and a node count in the batch.
proc ::vhdl_index::payload::summarize_parse {result descriptor interval limits registryVar countVar diagnosticLimit} {
    upvar 1 $registryVar registry $countVar references
    set parsed [parse_slot $result $descriptor $interval $limits]
    lassign [diagnostic_ids registry references [dict get $parsed diagnostics] $diagnosticLimit] ids complete
    set span [dict get $parsed span]
    return [list [dict create status [dict get $parsed status] token_interval $interval token_span $span \
        unresolved [dict get $parsed unresolved] diagnostic_ids $ids node_count [llength [dict get $parsed rows]]] $complete]
}

proc ::vhdl_index::payload::validate {view selections {requested {}} {intervalLimits {}}} {
    set result [qualified_result $view]
    set limits [batch_limits $requested]
    set state [new_collection $view $result {} [dict get $limits rows]]
    set reason {}
    set summaries {}
    set associations {}
    set outcomes {}
    set parsedTokens 0
    set parsedNodes 0
    set reused 0
    set unattempted 0
    set unavailable 0
    set evidence {}
    set diagnostics {}
    set references 0
    if {[llength $selections] > [dict get $limits selections]} {
        set reason selections
    } elseif {[catch {collect state $selections} summaries options]} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX PAYLOAD_ROW_LIMIT}} {
            return -options $options $summaries
        }
        set summaries {}
        set reason rows
    }
    set knownRows [dict size [dict get $state rows]]
    set diagnosticLimit [dict get $limits diagnostics]
    if {$reason eq {}} {
        foreach proof [ordered_evidence $state] {
            set id [dict get $proof evidence_id]
            set issues [field $proof diagnostics]
            if {[dict exists $proof diagnostic]} {lappend issues [dict get $proof diagnostic]}
            lassign [diagnostic_ids diagnostics references $issues $diagnosticLimit] ids complete
            lappend evidence [dict create evidence_id $id owner_id [dict get $proof owner_id] \
                span [dict get $proof span] availability [field $proof availability unavailable] diagnostic_ids $ids]
            if {!$complete} {
                set reason diagnostics
                break
            }
        }
    }
    if {$reason eq {}} {
        set tape [dict get $result tape]
        set cache {}
        foreach descriptor [ordered $state] {
            set presence [dict get $descriptor presence]
            set outcomeId {}
            set unresolved {}
            if {$presence eq "present"} {
                set interval [::vhdl_index::bounded::interval $tape [dict get $descriptor span]]
                set key [list [dict get $descriptor entry] $interval]
                if {[dict exists $cache $key]} {
                    set outcomeId [dict get $cache $key]
                    incr reused
                } else {
                    lassign $interval first last
                    if {[llength $outcomes] >= [dict get $limits parses]} {
                        set reason parses
                        break
                    }
                    if {$parsedTokens + $last - $first > [dict get $limits tokens]} {
                        set reason tokens
                        break
                    }
                    set outcomeId [llength $outcomes]
                    lassign [summarize_parse $result $descriptor $interval $intervalLimits diagnostics references $diagnosticLimit] \
                        outcome complete
                    dict set cache $key $outcomeId
                    incr parsedTokens [expr {$last - $first}]
                    incr parsedNodes [dict get $outcome node_count]
                    lappend outcomes $outcome
                    if {!$complete} {
                        set reason diagnostics
                    }
                }
                set status [dict get [lindex $outcomes $outcomeId] status]
                if {$status eq "unavailable"} {incr unavailable}
                if {$status ni {parsed ambiguous}} {set unresolved [list [dict get $descriptor span]]}
            } elseif {$presence eq "unavailable"} {
                incr unavailable
                set span [dict get $descriptor span]
                if {$span ne {}} {set unresolved [list $span]}
            }
            lassign [diagnostic_ids diagnostics references [dict get $descriptor diagnostics] $diagnosticLimit] ids complete
            dict unset descriptor diagnostics
            dict set descriptor diagnostic_ids $ids
            dict set descriptor outcome $outcomeId
            dict set descriptor unresolved $unresolved
            lappend associations $descriptor
            if {!$complete} {set reason diagnostics}
            if {$reason ne {}} {break}
        }
    }
    set unattempted [expr {$knownRows - [llength $associations]}]
    if {$reason in {rows selections}} {set unattempted unknown}
    set coverage [expr {$reason in {rows selections} ? "unavailable" : [coverage $state]}]
    return [dict create status [expr {$reason eq {} ? "finished" : "incomplete"}] limit $reason \
        source_id [dict get $result source_id] edition [dict get $result edition] selections $summaries \
        completeness $coverage rows $associations outcomes $outcomes evidence $evidence \
        diagnostics [dict keys $diagnostics] remaining $unattempted unavailable $unavailable \
        parsed_tokens $parsedTokens parsed_nodes $parsedNodes retained_nodes 0 reused $reused \
        duplicate_visits [dict get $state duplicate_visits] diagnostic_references $references]
}
