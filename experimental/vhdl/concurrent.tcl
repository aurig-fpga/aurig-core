# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc ::vhdl_index::parser::concurrent_candidate {state owner start status issue forms capabilities} {
    upvar 1 $state c
    set end [lindex [span c previous] 1]
    if {$owner ne {} && $end >= $start} {
        ::vhdl_index::ownership::gap c concurrent_candidates [list $start $end] \
            $status $capabilities $owner [list $issue] $forms
    }
}

proc ::vhdl_index::parser::concurrent_leaf {state owner ownerKind opening label} {
    upvar 1 $state c
    set first $c(i)
    set colon {}
    if {$label ne {}} {set colon [span c previous]}
    set postponed {}
    if {[peek c] eq "postponed"} {set postponed [take c]}
    set head [dict create label [lindex $label 0] label_span [lindex $label 1] \
        colon_span $colon postponed_span $postponed]
    if {[peek c] eq "assert"} {
        parse_concurrent c $owner $ownerKind $opening $head ASSERTION concurrent_assertion \
            {concurrent_assertions} ::vhdl_index::grammar::assertion
        return
    }
    if {[peek c] in {with <= <<}} {
        parse_assignment c $owner $ownerKind $opening $head {}
        return
    }
    set starter [peek c]
    set category {}
    set next $starter
    set target {}
    set components {}
    set targetIssue {}
    set c(grammarFence) [llength $c(significant)]
    set c(grammarDomain) INSTANTIATION
    if {$starter in {component entity configuration}} {
        if {$label eq {} && [is_name [peek c 1] 0] &&
            (($starter eq "entity" && [peek c 2] eq "is") ||
             ($starter eq "configuration" && [peek c 2] eq "of"))} {
            fail c UNSAFE_UNIT_BOUNDARY [list found $starter]
        }
        set category $starter
    } elseif {[is_name $starter 0]} {
        if {[catch {::vhdl_index::grammar::selected_name c 0 0 components 1} target options]} {
            if {[dict get $options -errorcode] ne {VHDL_INDEX INSTANTIATION}} {
                return -options $options $target
            }
            set targetIssue $target
            set target {}
        }
        set next [peek c]
        if {$next in {generic port}} {
            set category component
            if {[peek c -1] eq "all"} {
                set targetIssue [diagnostic c INSTANTIATION_EXPECTED_NAME [list span [span c previous]]]
            }
        }
    }
    if {$category ne {}} {
        parse_instance c $owner $ownerKind $opening $label $colon $category $starter $target $components $targetIssue $postponed
        return
    }
    if {$label ne {} && $postponed eq {} && $target ne {} && $next eq ";" && $ownerKind ne "entity"} {
        incr c(i)
        set issue [dict create code AMBIGUOUS_CONCURRENT_NAME severity info span $target]
        concurrent_candidate c $owner $opening recognized-but-unsupported $issue \
            {component_instantiation concurrent_procedure_call} {instantiations concurrent_procedure_calls}
        return
    }
    if {$target ne {}} {
        if {$next in {<= guarded transport inertial reject}} {
            parse_assignment c $owner $ownerKind $opening $head [name_target $target $components {}]
            return
        }
        if {$next in {( ' {;}}} {
            parse_named_concurrent c $owner $ownerKind $opening $head $target $components
            return
        }
    } elseif {$starter eq "("} {
        aggregate_concurrent c $owner $ownerKind $opening $head
        return
    }
    set c(i) $first
    opaque_concurrent c $ownerKind
    if {$targetIssue eq {}} {
        set targetIssue [dict create code UNRESOLVED_CONCURRENT_FORM severity info span [list $opening [lindex [span c previous] 1]]]
    }
    set capabilities [::vhdl_index::ownership::concurrent_profile $ownerKind]
    set forms {concurrent_assertion concurrent_procedure_call process_statement other_concurrent_statement}
    if {$ownerKind ne "entity"} {
        lappend forms concurrent_signal_assignment
        if {$postponed eq {}} {
            set forms [linsert $forms 0 component_instantiation]
            lappend capabilities instantiations map_associations
        }
    }
    concurrent_candidate c $owner $opening unrecognized $targetIssue $forms $capabilities
}

# Index one bounded production. On a local error the same cursor either
# reaches a proved sibling boundary or lets the enclosing transaction unwind.
proc ::vhdl_index::parser::parse_concurrent {state owner ownerKind opening head domain forms capabilities production args} {
    upvar 1 $state c
    set c(grammarFence) [llength $c(significant)]
    set c(grammarDomain) $domain
    set failed [catch {
        set row [$production c {*}$args]
        set tail [::vhdl_index::grammar::require c {;} EXPECTED_SEMICOLON]
        set region [list $opening [lindex $tail 1]]
    } issue options]
    if {$failed} {
        set code [dict get $options -errorcode]
        if {$code ne [list VHDL_INDEX $domain]} {return -options $options $issue}
        if {[string match *LIMIT [dict get $issue code]]} {
            return -code error -errorcode {VHDL_INDEX STRUCTURE} $issue
        }
        recover_concurrent c $owner $ownerKind $issue
        concurrent_candidate c $owner $opening malformed $issue $forms $capabilities
        return
    }
    set parameters {}
    if {[dict exists $row actual_parameters]} {set parameters [dict get $row actual_parameters]}
    foreach lexical [::vhdl_index::grammar::association_lexical c $region] {
        if {$parameters ne {}} {
            lassign [dict get $parameters association_content_span] a b
            set offset [lindex [dict get $lexical span] 0]
            if {$a <= $offset && $offset < $b} {continue}
        }
        concurrent_candidate c $owner $opening malformed $lexical $forms $capabilities
        return
    }
    if {$parameters ne {}} {
        if {[dict get $parameters association_validation] ne "parsed"} {
            ::vhdl_index::ownership::gap c actual_parameter_list [dict get $parameters association_group_span] \
                malformed {actual_parameter_associations} $owner [dict get $parameters association_diagnostics]
        }
    }
    lappend c(concurrentStatements) [dict merge $head $row [dict create span $region \
        terminator_span $tail owner_id $owner capability [lindex $capabilities 0] \
        status parsed diagnostics {} expression_status opaque]]
}

proc ::vhdl_index::parser::recover_concurrent {state owner ownerKind {issue {}}} {
    upvar 1 $state c
    if {$issue ne {} && [string match *EXPECTED*SEMICOLON [dict get $issue code]] &&
        [is_name [peek c] 0] && ![statement_label c]} {
        # A second name may start a sibling whose complete boundary is
        # unknown. The root transaction must account for that suffix.
        fail c UNPROVEN_CONCURRENT_BOUNDARY [list found [peek c]]
    }
    # A semicolon may fence the malformed text without proving the meaning
    # of a remaining name-shaped suffix. Account for the possible sibling.
    set tailStart $c(i)
    set tailForms {}
    set tailCapabilities {}
    if {$issue ne {} && [is_name [peek c] 0] && ![statement_label c]} {
        set next [peek c 1]
        if {$next in {( . ' {;}}} {
            lappend tailForms concurrent_procedure_call
            lappend tailCapabilities concurrent_procedure_calls
            if {$next ne ";"} {lappend tailCapabilities actual_parameter_associations}
        }
        if {$ownerKind ne "entity" && $next in {<= ( . '}} {
            lappend tailForms concurrent_signal_assignment
            lappend tailCapabilities concurrent_signal_assignments
        }
    }
    set tailSpan [span c]
    # Mode 2 stops at a sibling even when recovery starts at its first token.
    set ends {end elsif}
    if {$ownerKind eq "generate"} {lappend ends else when}
    while {1} {
        set marker [scan c [concat {{;} begin =>} $ends] {} {} {begin end} 2]
        if {$marker eq ";"} {incr c(i); break}
        if {$marker eq "eof"} {fail c TRUNCATED_SCOPE}
        if {$marker in {else when} && $marker in $ends} {
            if {[::vhdl_index::grammar::generate_alternative_start c]} {break}
            incr c(i)
        } elseif {$marker in $ends || ($marker eq "concurrent_candidate" && [peek c] ne "generate")} {
            break
        } else {
            fail c UNPROVEN_CONCURRENT_BOUNDARY [list found [peek c]]
        }
    }
    if {$tailForms ne {} && $c(i) > $tailStart} {
        set evidence [diagnostic c UNPROVEN_CONCURRENT_TAIL [list span $tailSpan \
            related_span [dict get $issue span] cause [dict get $issue code]]]
        concurrent_candidate c $owner [lindex $tailSpan 0] unrecognized $evidence $tailForms $tailCapabilities
    }
}

# Payload connectors are considered only at depth zero. Delimiter tracking
# is shared with scopes, and literals are single significant tokens.
proc ::vhdl_index::grammar::concurrent_payload {state stops missing} {
    upvar 1 $state c
    set first $c(i)
    set start [lindex [span c] 0]
    set mode 2
    set fenced [info exists c(sequentialGrammar)]
    if {$fenced} {set mode 0}
    set marker [scan c [concat $stops {{;} end begin elsif => := :}] {} {} {begin end} $mode $fenced]
    if {$marker eq "adjacent_payload"} {fail c UNPROVEN_CONCURRENT_BOUNDARY [list found [peek c]]}
    if {$c(i) == $first} {reject c $missing}
    if {[peek c -1] in {+ - * / ** & = /= < <= > >= => , to downto and or nand nor xor xnor not}} {
        reject c INCOMPLETE_PAYLOAD
    }
    return [extent c $start]
}

# The assertion production is independent of the concurrent statement
# label, postponed prefix, and enclosing semicolon.
proc ::vhdl_index::grammar::assertion {state} {
    upvar 1 $state c
    set keyword [require c assert EXPECTED_ASSERT]
    set stops {report severity else when ,}
    set condition [concurrent_payload c $stops MISSING_CONDITION]
    set reportKeyword {}
    set report {}
    set severityKeyword {}
    set severity {}
    if {[kind c] eq "report"} {
        set reportKeyword [take c]
        set report [concurrent_payload c $stops MISSING_REPORT]
    }
    if {[kind c] eq "severity"} {
        set severityKeyword [take c]
        set severity [concurrent_payload c $stops MISSING_SEVERITY]
    }
    if {[kind c] in {report severity}} {reject c CLAUSE_ORDER}
    return [dict create assert_span $keyword condition_span $condition \
        report_keyword_span $reportKeyword report_span $report severity_keyword_span $severityKeyword severity_span $severity]
}

# A final parenthesized group is a possible actual-parameter part.
# A following selected suffix or assignment operator instead makes it
# part of a name. Keep its ordinal so the association grammar can own it.
proc ::vhdl_index::grammar::concurrent_name_tail {state target components} {
    upvar 1 $state c
    set start [lindex $target 0]
    set suffixes {}
    set actuals {}
    while {[set next [kind c]] in {( . '}} {
        set actuals {}
        if {$next eq "("} {
            set actuals $c(i)
            set group [group c 0 2]
            lappend suffixes [dict create kind parenthesized span $group \
                content_status opaque empty [expr {$c(i) == $actuals + 2}]]
        } elseif {$next eq "."} {
            incr c(i)
            if {[kind c] eq "all"} {
                lappend components [take c]
            } else {
                lappend components [name_span c]
            }
        } else {
            set tick [take c]
            if {[kind c] in {range subtype}} {
                take c
            } else {
                name_span c
            }
            lappend suffixes [dict create kind attribute span [extent c [lindex $tick 0]]]
        }
    }
    return [list [extent c $start] $components $suffixes $actuals]
}

proc ::vhdl_index::parser::parse_named_concurrent {state owner ownerKind opening head target components} {
    upvar 1 $state c
    set c(grammarDomain) PROCEDURE_CALL
    set forms {concurrent_procedure_call}
    set capabilities {concurrent_procedure_calls actual_parameter_associations}
    if {$target ne {} && [peek c] in {( '}} {
        set prefixEnd $c(i)
        set failed [catch {::vhdl_index::grammar::concurrent_name_tail c $target $components} name options]
        if {$failed} {
            if {[dict get $options -errorcode] ne {VHDL_INDEX PROCEDURE_CALL}} {
                return -options $options $name
            }
            if {[string match *LIMIT [dict get $name code]]} {
                return -code error -errorcode {VHDL_INDEX STRUCTURE} $name
            }
            if {[statement_label c] && [peek c 2] in {block process postponed for if case}} {
                fail c UNCLOSED_DELIMITER
            }
            set c(i) $prefixEnd
            if {$ownerKind ne "entity"} {
                lappend forms concurrent_signal_assignment
                lappend capabilities concurrent_signal_assignments
            }
        } else {
            if {[peek c] in {<= guarded transport inertial reject}} {
                lassign $name full components suffixes
                parse_assignment c $owner $ownerKind $opening $head [name_target $full $components $suffixes]
                return
            }
            if {[peek c] ne ";"} {fail c UNPROVEN_CONCURRENT_BOUNDARY [list found [peek c]]}
            lassign $name full componentsFound suffixes actuals
            set target $full
            set components $componentsFound
            if {$actuals ne {}} {
                set c(i) $actuals
                set target [::vhdl_index::grammar::extent c [lindex $full 0]]
            }
        }
    }
    parse_concurrent c $owner $ownerKind $opening $head PROCEDURE_CALL $forms $capabilities \
        ::vhdl_index::grammar::procedure_call $target $components
}

proc ::vhdl_index::grammar::procedure_call {state target components} {
    upvar 1 $state c
    if {$target eq {}} {reject c EXPECTED_NAME}
    set parameters {}
    if {[kind c] eq "("} {
        set parameters [association_list c parameter 1]
    }
    return [dict create called_name_span $target called_name_components $components actual_parameters $parameters]
}

# The typed generate walker establishes the enclosing alternative. Here
# only check whether WHEN/ELSE can belong to its next header.
proc ::vhdl_index::grammar::generate_alternative_start {state} {
    upvar 1 $state c
    if {!$c(generateBodies)} {return 0}
    if {[kind c] eq "else"} {
        return [expr {[kind c 1] eq "generate" ||
            ([is_name [kind c 1] 0] && [kind c 2] eq ":" && [kind c 3] eq "generate")}]
    }
    if {[kind c] ne "when"} {return 0}
    set first $c(i)
    incr c(i)
    if {[statement_label c]} {incr c(i) 2}
    set failed [catch {
        scan c {=> when else elsif end begin {;}} {} {} {end begin} 2
    } marker options]
    set c(i) $first
    if {$failed} {return -options $options $marker}
    return [expr {$marker eq "=>"}]
}

proc ::vhdl_index::parser::name_target {target components suffixes} {
    return [dict create kind name span $target components $components suffixes $suffixes content_status opaque]
}

proc ::vhdl_index::parser::aggregate_concurrent {state owner ownerKind opening head} {
    upvar 1 $state c
    set c(grammarDomain) SIGNAL_ASSIGNMENT
    set first $c(i)
    set failed [catch {::vhdl_index::grammar::group c 0 2} group options]
    if {$failed} {
        if {[dict get $options -errorcode] eq {VHDL_INDEX SIGNAL_ASSIGNMENT}} {
            return -code error -errorcode {VHDL_INDEX STRUCTURE} $group
        }
        return -options $options $group
    }
    if {[peek c] eq "<="} {
        set target [dict create kind aggregate span $group content_status opaque empty [expr {$c(i) == $first + 2}]]
        parse_assignment c $owner $ownerKind $opening $head $target
        return
    }
    set issue [diagnostic c PROCEDURE_CALL_EXPECTED_NAME [list span $group]]
    recover_concurrent c $owner $ownerKind
    concurrent_candidate c $owner $opening malformed $issue \
        {concurrent_procedure_call concurrent_signal_assignment} \
        {concurrent_procedure_calls actual_parameter_associations concurrent_signal_assignments}
}

proc ::vhdl_index::parser::parse_assignment {state owner ownerKind opening head target} {
    upvar 1 $state c
    parse_concurrent c $owner $ownerKind $opening $head SIGNAL_ASSIGNMENT concurrent_signal_assignment \
        {concurrent_signal_assignments} ::vhdl_index::grammar::concurrent_assignment $ownerKind $target
}

proc ::vhdl_index::grammar::assignment_target {state} {
    upvar 1 $state c
    set first $c(i)
    if {[kind c] eq "("} {
        set item [group c 0 2]
        return [dict create kind aggregate span $item content_status opaque empty [expr {$c(i) == $first + 2}]]
    }
    if {[kind c] eq "<<"} {
        set item [group c 0 2]
        set components {}
    } elseif {[is_name [kind c] 0]} {
        set item [selected_name c 0 0 components 1]
    } else {
        reject c MISSING_TARGET
    }
    lassign [concurrent_name_tail c $item $components] full parts suffixes
    return [name_target $full $parts $suffixes]
}

proc ::vhdl_index::grammar::concurrent_assignment {state ownerKind target} {
    upvar 1 $state c
    set with {}
    set selector {}
    set select {}
    set matching {}
    if {[kind c] eq "with"} {
        set with [take c]
        set selector [concurrent_payload c {select , when else} MISSING_SELECTOR]
        set select [require c select EXPECTED_SELECT]
        if {[kind c] eq "?" ||
            ([kind c] eq "invalid" && [::vhdl_index::slice $c(snapshot) [span c]] eq "?")} {
            set matching [take c]
            if {$c(edition) < 2008} {reject c EDITION_MATCHING_SELECTION [list span $matching]}
        }
        set target [assignment_target c]
    }
    if {$target eq {}} {set target [assignment_target c]}
    if {[dict exists $target empty] && [dict get $target empty]} {
        reject c EMPTY_TARGET [list span [dict get $target span]]
    }
    if {[dict exists $target suffixes]} {
        foreach suffix [dict get $target suffixes] {
            if {[dict exists $suffix empty] && [dict get $suffix empty]} {
                reject c EMPTY_TARGET_SUFFIX [list span [dict get $suffix span]]
            }
        }
    }
    set op [require c <= EXPECTED_OPERATOR]
    set guarded {}
    if {[kind c] eq "guarded"} {set guarded [take c]}
    set delay [delay_mechanism c]
    if {[kind c] in {force release}} {reject c CONCURRENT_FORCE_RELEASE}
    if {$with eq {}} {
        lassign [conditional_waveforms c] category rows
    } else {
        set category selected
        set rows [selected_waveforms c]
    }
    if {$ownerKind eq "entity"} {reject c OUT_OF_CONTEXT [list span $op]}
    return [dict create category $category target $target target_span [dict get $target span] \
        operator_span $op guarded_span $guarded delay $delay alternatives $rows \
        with_span $with selector_span $selector select_span $select matching_span $matching]
}
