# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::payload {}

# Retained lists are ordered and disjoint within each carrier family.
# The enclosing row can also carry a qualified nested occurrence.
proc ::vhdl_index::payload::candidate_rows {rows wanted} {
    if {$wanted eq {}} {return $rows}
    set low 0
    set high [llength $rows]
    while {$low < $high} {
        set mid [expr {($low + $high) / 2}]
        set start [lindex [dict get [lindex $rows $mid] span] 0]
        if {$start <= $wanted} {
            set low [expr {$mid + 1}]
        } else {
            set high $mid
        }
    }
    if {$low == 0} {return {}}
    set row [lindex $rows [expr {$low - 1}]]
    if {$wanted > [lindex [dict get $row span] 1]} {return {}}
    return [list $row]
}

proc ::vhdl_index::payload::clauses {collection clauses} {
    upvar 1 $collection state
    foreach clause [candidate_rows $clauses [lindex [dict get $state wanted] 1]] {
        if {[field $clause status] ne "parsed"} {
            set id [::vhdl_index::regions::identity [dict get $state view] \
                [list interface_clause [lindex [dict get $clause span] 0]]]
            record_evidence state $id [dict create evidence_id $id owner_id [dict get $state owner] \
                kind interface_clause span [dict get $clause span] status [dict get $clause status] \
                diagnostics [dict get $clause diagnostics]]
        }
        interface_items state $clause [dict get $clause kind]
    }
}

proc ::vhdl_index::payload::interface_items {collection listRecord context} {
    upvar 1 $collection state
    foreach item [candidate_rows [field $listRecord items] [lindex [dict get $state wanted] 1]] {
        set form [dict get $item category]
        set at [lindex [dict get $item span] 0]
        set kind [expr {$context eq "parameter" ? "parameter" : "interface_item"}]
        set id [list $kind $at]
        switch -- $form {
            object {
                if {![interested state $id]} {continue}
                set class [dict get $item effective_class]
                set mode [dict get $item effective_mode]
                if {$class ne "file" && $mode ne "linkage" &&
                    ($context ne "parameter" || ($class ne "signal" && ($class ne "variable" || $mode eq "in")))} {
                    slot state $id ${context}_default expression $item default_span optional default_marker_span
                } elseif {[dict get $item default_marker_span] ne {}} {
                    slot state $id ${context}_default expression $item default_span optional default_marker_span
                }
            }
            unknown {
                slot state $id ${context}_default expression $item default_span required
            }
            subprogram {
                if {[dict exists $item parameters]} {interface_items state [dict get $item parameters] parameter}
                interested state $id
            }
            default {interested state $id}
        }
    }
}

proc ::vhdl_index::payload::region_sites {collection address kind row} {
    upvar 1 $collection state
    set at [lindex $address 1]
    set syntax [field $row syntax]
    lassign [dict get $state wanted] wantedKind wantedAt
    switch -- $kind {
        block {
            slot state $address block_guard expression $syntax guard_span optional
        }
        generate_alternative {
            if {[dict get $syntax form] in {if elsif}} {
                slot state $address generate_condition expression $syntax condition_span required
            }
        }
        case_generate {
            slot state $address generate_selector expression $syntax selector_span required
        }
        for_generate {
            set parameter [dict get $syntax parameter]
            parameter_range state generate_parameter $parameter
        }
        if_alternative {
            if {[dict get $syntax form] in {if elsif}} {
                slot state $address if_condition expression $syntax condition_span required
            }
        }
    }
    if {$wantedKind in {{} interface_item parameter}} {clauses state [field $syntax interfaces]}
    if {$wantedKind in {{} declaration}} {
        object_sites state $row
        foreach declaration [candidate_rows [field $row declarations] $wantedAt] {
            set id [list declaration [lindex [dict get $declaration span] 0]]
            if {![interested state $id]} {continue}
            switch -- [dict get $declaration kind] {
                attribute_specification {
                    slot state $id attribute_value expression $declaration value_span required
                }
                attribute {
                    if {[dict get $declaration status] ne "parsed"} {
                        slot state $id attribute_value expression $declaration value_span required
                    }
                }
                file_object {
                    slot state $id file_open_kind expression $declaration open_kind_span optional open_span
                    slot state $id file_logical_name expression $declaration logical_name_span optional is_span
                }
                disconnect {slot state $id disconnect_time expression $declaration time_span required}
            }
        }
    }
    if {$wantedKind in {{} declaration array_dimension}} {
        foreach declaration [candidate_rows [field $row types] $wantedAt] {type_sites state $declaration}
    }
    set result [dict get $state result]
    foreach {capability occurrence} {
        concurrent_assertions concurrent_assertion concurrent_signal_assignments concurrent_signal_assignment
    } {
        if {$wantedKind ne {} && $wantedKind ne $occurrence &&
            !($occurrence eq "concurrent_signal_assignment" && [assignment_child $wantedKind])} {continue}
        foreach statement [candidate_rows [::vhdl_index::concurrent_at $result $address $capability] $wantedAt] {
            statement_sites state $occurrence $statement
        }
    }
    if {$wantedKind eq "concurrent_procedure_call"} {
        foreach statement [candidate_rows [::vhdl_index::concurrent_at $result $address concurrent_procedure_calls] $wantedAt] {
            statement_sites state $wantedKind $statement
        }
    }
    dict for {capability statements} [field $row sequential] {
        if {$capability in {sequential_procedure_calls null_statements}} {
            if {$wantedKind ni {sequential_procedure_call null_statement}} {continue}
        }
        foreach statement [candidate_rows $statements $wantedAt] {
            set occurrence [dict get $statement sequential_kind]
            if {$wantedKind ne {} && $wantedKind ne $occurrence &&
                !($occurrence in {variable_assignment sequential_signal_assignment} &&
                    [assignment_child $wantedKind])} {continue}
            statement_sites state $occurrence $statement
        }
    }
}

proc ::vhdl_index::payload::object_sites {collection row} {
    upvar 1 $collection state
    set result [dict get $state result]
    set tape [dict get $result tape]
    set wanted [lindex [dict get $state wanted] 1]
    set starts [dict get $tape starts]
    set significant [dict get $tape significant]
    set entries [field $row entries]
    if {$wanted ne {}} {
        set low 0
        set high [llength $entries]
        while {$low < $high} {
            set mid [expr {($low + $high) / 2}]
            set first [lindex [lindex $entries $mid] 0]
            set offset [lindex $starts [lindex $significant $first]]
            if {$offset <= $wanted} {
                set low [expr {$mid + 1}]
            } else {
                set high $mid
            }
        }
        if {$low == 0} {return}
        set entries [list [lindex $entries [expr {$low - 1}]]]
    }
    foreach entry $entries {
        lassign $entry first count
        set lo 0
        set hi $count
        if {$wanted ne {}} {
            while {$lo < $hi} {
                set mid [expr {($lo + $hi) / 2}]
                set ordinal [expr {$first + 5 * $mid}]
                set offset [lindex $starts [lindex $significant $ordinal]]
                if {$offset < $wanted} {
                    set lo [expr {$mid + 1}]
                } else {
                    set hi $mid
                }
            }
            if {$lo == $count ||
                [lindex $starts [lindex $significant [expr {$first + 5 * $lo}]]] ne $wanted} {continue}
            set hi [expr {$lo + 1}]
        }
        for {set index $lo} {$index < $hi} {incr index} {
            set object [::vhdl_index::object::record $result $row $entry $index]
            set id [list declaration [lindex [dict get $object span] 0]]
            slot state $id object_initializer expression $object init_span optional init_marker_span
        }
    }
}

proc ::vhdl_index::payload::type_sites {collection row} {
    upvar 1 $collection state
    set id [list declaration [lindex [dict get $row span] 0]]
    interested state $id
    switch -- [dict get $row kind] {
        scalar_range - physical {
            slot state $id scalar_range discrete_range $row range_payload_span required
        }
        subtype - access {range_constraint state $id $row}
        array {
            if {[field $row constraint_span] ne {}} {range_constraint state $id $row}
            set dimensions [field $row dimensions]
            if {$dimensions eq {} && [dict get $row status] ne "parsed"} {
                slot state $id array_dimension_range discrete_range $row range_payload_span required
            }
            foreach dimension $dimensions {
                set child [list array_dimension [lindex [dict get $dimension span] 0]]
                set carrier [dict merge $dimension [dict create status [dict get $row status] \
                    diagnostics [dict get $row diagnostics]]]
                if {[dict get $dimension kind] eq "index_subtype"} {
                    slot state $child array_dimension_box {} $carrier box_span required
                } else {
                    slot state $child array_dimension_range discrete_range $carrier span required
                }
            }
        }
        type {
            # Recovery recognized a type declaration but did not establish
            # its form or an interval for any of its potential payloads.
            if {[dict get $row status] ne "parsed"} {
                slot state $id type_payload {} $row range_payload_span required
            }
        }
    }
}

# Structured subtype carriers prove the constraint extent. Its first
# significant token distinguishes a RANGE constraint from a composite one.
proc ::vhdl_index::payload::range_constraint {collection id row} {
    upvar 1 $collection state
    if {![interested state $id]} {return}
    set constraint [field $row constraint_span]
    if {$constraint eq {}} {
        slot state $id subtype_range discrete_range $row range_payload_span optional
        return
    }
    set tape [dict get $state result tape]
    set significant [dict get $tape significant]
    set first [lindex [::vhdl_index::bounded::interval $tape $constraint] 0]
    if {[lindex [::vhdl_index::lexer::token $tape [lindex $significant $first]] 0] eq "range"} {
        set start [lindex [dict get $tape starts] [lindex $significant [expr {$first + 1}]]]
        set carrier [dict merge $row [dict create range_payload_span [list $start [lindex $constraint 1]]]]
        slot state $id subtype_range discrete_range $carrier range_payload_span required
    }
}

proc ::vhdl_index::payload::parameter_range {collection kind row} {
    upvar 1 $collection state
    set extent [field [field $row range] span]
    set carrier [dict merge $row [dict create range_payload_span $extent]]
    set id [list $kind [lindex [dict get $row span] 0]]
    set role [expr {$kind eq "loop_parameter" ? "for_loop_range" : "for_generate_range"}]
    slot state $id $role discrete_range $carrier range_payload_span required
}

proc ::vhdl_index::payload::statement_sites {collection occurrence row} {
    upvar 1 $collection state
    set id [list $occurrence [lindex [dict get $row span] 0]]
    set selected [interested state $id]
    if {!$selected && $occurrence ni {concurrent_signal_assignment sequential_signal_assignment variable_assignment}} {return}
    switch -- $occurrence {
        concurrent_assertion - sequential_assertion {
            slot state $id assert_condition expression $row condition_span required
            slot state $id assert_report expression $row report_span optional report_keyword_span
            slot state $id assert_severity expression $row severity_span optional severity_keyword_span
        }
        report_statement {
            slot state $id report_value expression $row report_span required
            slot state $id report_severity expression $row severity_span optional severity_keyword_span
        }
        wait_statement {
            slot state $id wait_condition expression $row condition_span optional until_span
            slot state $id wait_timeout expression $row timeout_span optional for_span
        }
        return_statement {
            slot state $id return_value expression $row expression_span optional
        }
        next_statement - exit_statement {
            set role [expr {$occurrence eq "next_statement" ? "next_condition" : "exit_condition"}]
            slot state $id $role expression $row condition_span optional when_span
        }
        sequential_control_envelope {
            switch -- [dict get $row kind] {
                case {slot state $id case_selector expression $row selector_span required}
                loop {
                    if {[dict get $row iteration_kind] eq "while"} {
                        slot state $id while_condition expression $row condition_span required
                    }
                }
            }
        }
        loop_parameter {parameter_range state $occurrence $row}
        concurrent_signal_assignment - sequential_signal_assignment - variable_assignment {
            assignment_sites state $id $row
        }
    }
}

proc ::vhdl_index::payload::assignment_child {kind} {
    return [expr {$kind in {assignment_alternative waveform_element}}]
}

proc ::vhdl_index::payload::assignment_sites {collection id row} {
    upvar 1 $collection state
    set form [lindex $id 0]
    if {[field $row release_span] ne {}} {return}
    slot state $id assignment_selector expression $row selector_span optional with_span
    set status [dict get $row status]
    set issues [dict get $row diagnostics]
    if {$form ne "variable_assignment"} {
        set delay [dict merge [field $row delay] [dict create status $status diagnostics $issues]]
        slot state $id reject_time expression $delay reject_time_span optional reject_span
    }
    set alternatives [field $row alternatives]
    if {$alternatives eq {} && $status ne "parsed"} {
        slot state $id assignment_payload expression $row expression_span required
    }
    foreach alternative $alternatives {
        set carrier [dict merge $alternative [dict create status $status diagnostics $issues]]
        set child [list assignment_alternative [lindex [dict get $carrier span] 0]]
        interested state $child
        if {[dict get $row category] eq "conditional"} {
            slot state $child assignment_condition expression $carrier condition_span optional when_span
        }
        if {[dict exists $carrier expression_span]} {
            set role [expr {$form eq "variable_assignment" ? "variable_value" : "force_value"}]
            slot state $child $role expression $carrier expression_span required
        } elseif {[field $carrier unaffected_span] ne {}} {
            slot state $child unaffected_waveform {} $carrier unaffected_span required
        } else {
            foreach element [dict get $carrier elements] {
                set item [dict merge $element [dict create status $status diagnostics $issues]]
                set elementId [list waveform_element [lindex [dict get $item span] 0]]
                if {[dict get $item kind] eq "null"} {
                    slot state $elementId null_waveform {} $item value_span required
                } else {
                    slot state $elementId waveform_value expression $item value_span required
                }
                slot state $elementId waveform_delay expression $item delay_span optional after_span
            }
        }
    }
}
