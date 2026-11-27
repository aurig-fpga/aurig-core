# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# The opening proves a sequential owner candidate. If the typed boundary
# fails, preserve its loss and any enclosed evidence for the outer rollback.
proc ::vhdl_index::parser::sequential_scope {state kind name depth ownership shapeVar formals syntax} {
    upvar 1 $state c
    if {$shapeVar ne {}} {
        upvar 1 $shapeVar shape
        set shapeVar shape
    }
    set checkpoint [::vhdl_index::ownership::checkpoint c]
    set failed [catch {scope c $kind $name $depth require $ownership $shapeVar $formals $syntax} tail options]
    if {$failed && [dict get $options -errorcode] eq {VHDL_INDEX STRUCTURE}} {
        lassign $ownership owner parent
        set extent [list $owner [lindex [span c] 0]]
        ::vhdl_index::ownership::rollback c $checkpoint $kind $extent $tail $parent
    }
    return -options $options $tail
}

proc ::vhdl_index::parser::branch_header {state marker} {
    upvar 1 $state c
    set start $c(i)
    if {[boundary c [list $marker {;} end begin generate elsif else when]] ne $marker} {
        fail c INCOMPLETE_BRANCH_HEADER [list expected $marker]
    }
    if {$start == $c(i)} {
        lappend c(diagnostics) [diagnostic c INCOMPLETE_BRANCH_HEADER [list expected $marker]]
    }
    incr c(i)
}

proc ::vhdl_index::parser::sequential_opaque_control {state depth kind name matching} {
    upvar 1 $state c
    set active {}
    if {$name ne {}} {set active [open_named_scope c $kind $name]}
    if {$kind eq "case"} {
        expect c when
        branch_header c =>
    }
    set sawElse 0
    while {1} {
        set next [peek c]
        if {$next eq "end"} {break}
        if {$kind eq "if" && $next in {elsif else} && !$sawElse} {
            incr c(i)
            if {$next eq "elsif"} {
                branch_header c then
            } else {
                set sawElse 1
            }
        } elseif {$kind eq "case" && [accept c when]} {
            branch_header c =>
        } else {
            sequential_statement c $depth {} {}
        }
    }
    set tail [terminator c $kind $name 1 $matching]
    if {$active ne {}} {close_named_scope c $active}
    return $tail
}

# Prove the connector separately from the opaque payload.
proc ::vhdl_index::parser::sequential_payload {state stops} {
    upvar 1 $state c
    set first $c(i)
    set start [lindex [span c] 0]
    set marker [scan c [concat $stops {{;} end begin generate elsif else when}] {} {} {begin end} 0 0 header]
    set payload {}
    if {$c(i) > $first} {set payload [::vhdl_index::grammar::extent c $start]}
    return [list $marker $payload]
}

proc ::vhdl_index::parser::sequential_header {state connector issuesVar} {
    upvar 1 $state c $issuesVar issues
    lassign [sequential_payload c [list $connector]] marker payload
    if {$marker ne $connector || $payload eq {}} {
        lappend issues [diagnostic c INCOMPLETE_BRANCH_HEADER [list expected $connector found $marker]]
        lappend c(diagnostics) [lindex $issues end]
    }
    set connectorSpan {}
    if {$marker eq $connector} {set connectorSpan [take c]}
    return [list $payload $connectorSpan]
}

proc ::vhdl_index::parser::sequential_sequence {state depth owner bodyKind alternatives rowsVar} {
    upvar 1 $state c $rowsVar rows
    while {[peek c] ni {end elsif else when}} {
        sequential_statement c $depth $owner $bodyKind rows $alternatives
    }
}

proc ::vhdl_index::parser::sequential_alternative {state depth kind owner bodyKind control syntax valid issue alternatives} {
    upvar 1 $state c
    set anchor [lindex [dict get $syntax keyword_span] 0]
    set bodyStart [lindex [span c previous] 1]
    set checkpoint [::vhdl_index::ownership::checkpoint c]
    set rows {}
    sequential_sequence c $depth $anchor $bodyKind $alternatives rows
    set boundary [lindex [span c] 0]
    set extent [list $anchor $boundary]
    if {$valid} {
        lappend c(sequentialRegions) [dict create id $anchor parent_id $owner kind $kind span $extent \
            sequential_span [list $bodyStart $boundary] sequential $rows syntax $syntax control_start $control]
    } else {
        ::vhdl_index::ownership::rollback c $checkpoint $kind $extent $issue $owner
    }
    return $anchor
}

proc ::vhdl_index::parser::sequential_if {state depth owner bodyKind start opener issuesVar} {
    upvar 1 $state c $issuesVar controlIssues
    set form if
    set keyword $opener
    set sawElse 0
    set alternatives {}
    set partial 0
    while {1} {
        set issues {}
        set condition {}
        set connector {}
        if {$sawElse} {
            lappend issues [diagnostic c UNEXPECTED_ALTERNATIVE [list found $form span $keyword]]
            lappend c(diagnostics) {*}$issues
        }
        set ordered [expr {!$sawElse}]
        if {$form eq "else"} {
            set sawElse 1
        } else {
            lassign [sequential_header c then issues] condition connector
        }
        set valid [expr {$ordered && ($connector ne {} || $form eq "else")}]
        set syntax [dict create form $form keyword_span $keyword condition_span $condition connector_span $connector \
            status [expr {$issues eq {} ? "parsed" : "malformed"}] diagnostics $issues]
        lappend alternatives [sequential_alternative c $depth if_alternative $owner $bodyKind $start \
            $syntax $valid [lindex $issues 0] {elsif else}]
        if {!$valid} {set partial 1}
        lappend controlIssues {*}$issues
        set form [peek c]
        if {$form ni {elsif else}} {break}
        set keyword [take c]
    }
    return [dict create matching_span {} alternative_owners $alternatives \
        interior_status [expr {$partial ? "partial" : "structured"}]]
}

proc ::vhdl_index::parser::sequential_choices {state issuesVar} {
    upvar 1 $state c $issuesVar issues
    set choices {}
    set separators {}
    while {1} {
        set soleOthers [expr {[peek c] eq "others" && [peek c 1] in {| =>}}]
        lassign [sequential_payload c {| =>}] marker extent
        if {$extent eq {}} {
            lappend issues [diagnostic c CASE_MISSING_CHOICE {}]
        } else {
            lappend choices [dict create kind [expr {$soleOthers ? "others" : "opaque"}] span $extent]
        }
        if {$marker ne "|"} {break}
        lappend separators [take c]
    }
    set arrow {}
    if {$marker eq "=>"} {
        set arrow [take c]
    } else {
        lappend issues [diagnostic c CASE_MISSING_ARROW [list found $marker]]
    }
    lappend c(diagnostics) {*}$issues
    return [list $choices $separators $arrow]
}

proc ::vhdl_index::parser::sequential_case {state depth owner bodyKind start opener issuesVar} {
    upvar 1 $state c $issuesVar controlIssues
    set matching {}
    if {[peek c] eq "?"} {
        set matching [take c]
        while {[peek c] eq "?"} {
            set issue [diagnostic c DUPLICATE_CASE_MARKER {}]
            lappend controlIssues $issue
            lappend c(diagnostics) $issue
            incr c(i)
        }
    }
    lassign [sequential_header c is controlIssues] selector connector
    set partial 0
    if {[peek c] ne "when"} {
        set issue [diagnostic c CASE_EXPECTED_WHEN {}]
        lappend controlIssues $issue
        lappend c(diagnostics) $issue
        set begin [lindex [span c] 0]
        set ignored {}
        sequential_sequence c $depth {} $bodyKind {when} ignored
        if {$begin < [lindex [span c] 0]} {
            set partial 1
            ::vhdl_index::ownership::gap c sequential_subtree [list $begin [lindex [span c] 0]] \
                unrecognized [::vhdl_index::ownership::sequential_profile root] $owner [list $issue]
        }
    }
    set alternatives {}
    while {[peek c] eq "when"} {
        set keyword [take c]
        set issues {}
        lassign [sequential_choices c issues] choices separators arrow
        set valid [expr {$arrow ne {}}]
        set syntax [dict create form when keyword_span $keyword choices $choices choice_separator_spans $separators \
            arrow_span $arrow status [expr {$issues eq {} ? "parsed" : "malformed"}] diagnostics $issues]
        lappend alternatives [sequential_alternative c $depth case_alternative $owner $bodyKind $start \
            $syntax $valid [lindex $issues end] {when}]
        if {!$valid} {set partial 1}
        lappend controlIssues {*}$issues
    }
    return [dict create matching_span $matching selector_span $selector is_span $connector alternative_owners $alternatives \
        interior_status [expr {$partial ? "partial" : "structured"}]]
}

proc ::vhdl_index::parser::sequential_control {state depth owner bodyKind start label colon kind opener} {
    upvar 1 $state c
    set active {}
    if {$label ne {}} {set active [open_named_scope c $kind $label]}
    set issues {}
    set shape [sequential_$kind c $depth $owner $bodyKind $start $opener issues]
    set before [llength $c(diagnostics)]
    set tail [terminator c $kind $label 1 [expr {[dict get $shape matching_span] ne {}}] 0 0 closing]
    if {$active ne {}} {close_named_scope c $active}
    lappend issues {*}[lrange $c(diagnostics) $before end]
    set extent [list $start [lindex $tail 1]]
    return [dict merge $shape $closing [dict create sequential_kind sequential_control_envelope kind $kind span $extent \
        owner_id $owner label [lindex $label 0] label_span [lindex $label 1] colon_span $colon opener_span $opener \
        terminator_span $tail status [expr {$issues eq {} ? "parsed" : "malformed"}] diagnostics $issues]]
}

# Walk each statement once. The bounded leaf grammar reuses the established fence.
proc ::vhdl_index::parser::sequential_statement {state depth owner bodyKind {rowsVar {}} {alternatives {}}} {
    upvar 1 $state c
    if {$rowsVar ne {}} {upvar 1 $rowsVar rows}
    set start [lindex [span c] 0]
    set label [optional_label c]
    set colon {}
    if {$label ne {}} {set colon [span c previous]}
    set head [peek c]
    switch -- $head {
        if - case - for - while - loop {
            set firstIssue [llength $c(diagnostics)]
            set opener [take c]
            if {$head in {if case} && $owner ne {}} {
                dict lappend rows control_flow_envelopes \
                    [sequential_control c [descend c $depth] $owner $bodyKind $start $label $colon $head $opener]
                return
            }
            set matching {}
            set kind $head
            switch -- $head {
                if {branch_header c then}
                case {
                    if {[peek c] eq "?"} {set matching [take c]}
                    branch_header c is
                }
                for - while {
                    branch_header c loop
                    set kind loop
                }
            }
            set tail [sequential_opaque_control c [descend c $depth] $kind $label [expr {$matching ne {}}]]
            if {$owner ne {}} {
                set region [list $start [lindex $tail 1]]
                set issues [lrange $c(diagnostics) $firstIssue end]
                set status [expr {$issues eq {} ? "parsed" : "malformed"}]
                dict lappend rows control_flow_envelopes [dict create sequential_kind sequential_control_envelope \
                    kind $kind span $region owner_id $owner label [lindex $label 0] label_span [lindex $label 1] colon_span $colon \
                    opener_span $opener matching_span $matching terminator_span $tail interior_status opaque \
                    status $status diagnostics $issues]
                ::vhdl_index::ownership::gap c sequential_control $region recognized-but-unsupported \
                    [::vhdl_index::ownership::sequential_profile root] $owner $issues
            }
        }
        block - process {fail c UNEXPECTED_CONCURRENT_SCOPE}
        entity - architecture - package - context - configuration - component {
            fail c UNSAFE_UNIT_BOUNDARY [list found $head]
        }
        else - elsif - when {fail c UNEXPECTED_ALTERNATIVE [list found $head]}
        default {
            set row [sequential_leaf c $owner $bodyKind $start $label $colon $head $alternatives]
            if {$row ne {}} {dict lappend rows [dict get $row capability] $row}
        }
    }
}

proc ::vhdl_index::parser::sequential_leaf {state owner ownerKind start label colon head alternatives} {
    upvar 1 $state c
    set first $c(i)
    set modifier {}
    if {$head eq "postponed"} {
        set modifier [take c]
        set head [peek c]
        if {$head in {block process if case for while loop postponed}} {
            fail c UNPROVEN_SEQUENTIAL_BOUNDARY [list found $head]
        }
    }
    set body $c(i)
    if {$head eq "null" && [peek c 1] in {identifier extended_identifier ( <<}} {
        # NULL has no payload. A name or target-shaped prefix is a possible sibling.
        incr c(i)
        set marker sequential_sibling
    } else {
        set marker [scan c {{;} end begin elsif =>} {} {} {begin end} 0 0 [list $head $alternatives]]
    }
    set fence $c(i)
    if {$marker eq "eof"} {fail c TRUNCATED_SCOPE}
    if {$marker eq "begin" && $c(i) == $first} {fail c UNEXPECTED_BOUNDARY [list found $marker]}
    if {$marker in {begin =>}} {fail c UNPROVEN_SEQUENTIAL_BOUNDARY [list found $marker]}
    set semicolon {}
    set issues {}
    if {$marker eq ";"} {
        set semicolon [take c]
    } elseif {$c(i) > $first} {
        set issue [diagnostic c MISSING_SEMICOLON [list span [list $start [lindex [span c] 0]]]]
        if {$marker eq "end" || $owner eq {}} {lappend c(diagnostics) $issue}
        lappend issues $issue
    } else {
        fail c UNPROVEN_SEQUENTIAL_BOUNDARY [list found $marker]
    }
    if {$owner eq {}} {return {}}
    set after $c(i)
    set region [::vhdl_index::grammar::extent c $start]
    set c(grammarFence) $fence
    set c(i) $body
    set c(sequentialGrammar) 1
    set family {}
    set capability {}
    set prefix {}
    set c(grammarDomain) SEQUENTIAL_STATEMENT
    set failed [catch {
        switch -- $head {
            assert {
                set family sequential_assertion
                set capability sequential_assertions
                set c(grammarDomain) SEQUENTIAL_ASSERTION
                ::vhdl_index::grammar::assertion c
            }
            report {
                set family report_statement
                set capability report_statements
                set c(grammarDomain) SEQUENTIAL_REPORT
                ::vhdl_index::grammar::report_statement c
            }
            null {
                set family null_statement
                set capability null_statements
                set c(grammarDomain) SEQUENTIAL_NULL
                dict create null_span [take c]
            }
            wait {
                set family wait_statement
                set capability wait_statements
                set c(grammarDomain) SEQUENTIAL_WAIT
                ::vhdl_index::grammar::wait_statement c
            }
            return {
                set family return_statement
                set capability return_statements
                set c(grammarDomain) SEQUENTIAL_RETURN
                ::vhdl_index::grammar::return_statement c $ownerKind
            }
            next - exit {
                set family ${head}_statement
                set capability ${head}_statements
                set c(grammarDomain) SEQUENTIAL_[string toupper $head]
                ::vhdl_index::grammar::loop_transfer c $head
            }
            with - identifier - extended_identifier - << - ( - := - <= {
                set c(grammarDomain) SEQUENTIAL_STATEMENT
                set selection {}
                set target {}
                set actuals {}
                if {$head eq "with"} {set selection [::vhdl_index::grammar::selection_header c]}
                set next [::vhdl_index::grammar::kind c]
                if {$next ni {:= <=}} {
                    set target [::vhdl_index::grammar::assignment_target c actuals]
                    set next [::vhdl_index::grammar::kind c]
                }
                if {$next in {:= <=}} {
                    if {$next eq ":="} {
                        set family variable_assignment
                        set capability variable_assignments
                        set c(grammarDomain) VARIABLE_ASSIGNMENT
                    } else {
                        set family sequential_signal_assignment
                        set capability sequential_signal_assignments
                        set c(grammarDomain) SEQUENTIAL_SIGNAL_ASSIGNMENT
                    }
                    lassign $selection with selector select matching
                    set prefix [dict create target $target target_span {} operator_span [span c] \
                        with_span $with selector_span $selector select_span $select matching_span $matching]
                    if {$target ne {}} {dict set prefix target_span [dict get $target span]}
                    ::vhdl_index::grammar::sequential_assignment c $target $selection $next
                } elseif {$selection eq {} && $next eq "eof" && $head in {identifier extended_identifier}} {
                    set family sequential_procedure_call
                    set capability sequential_procedure_calls
                    set c(grammarDomain) SEQUENTIAL_CALL
                    ::vhdl_index::grammar::sequential_call c $target $actuals
                } else {
                    ::vhdl_index::grammar::reject c UNSUPPORTED_NAME_FORM
                }
            }
            default {dict create}
        }
    } fields options]
    if {!$failed && $family ne {} && [::vhdl_index::grammar::kind c] ne "eof"} {
        lappend issues [::vhdl_index::grammar::problem c UNEXPECTED_TOKEN [list found [peek c]]]
    }
    unset c(sequentialGrammar)
    set c(i) $after
    if {$failed} {
        if {[dict get $options -errorcode] ne [list VHDL_INDEX $c(grammarDomain)]} {
            return -options $options $fields
        }
        lappend issues $fields
        set fields $prefix
    }
    if {$family eq {}} {
        set status unrecognized
        if {$head in {<< string} || ($head in {identifier extended_identifier} && $semicolon ne {} &&
            [llength $issues] == 1 && [dict get [lindex $issues 0] code] eq "SEQUENTIAL_STATEMENT_UNSUPPORTED_NAME_FORM")} {
            set status recognized-but-unsupported
        }
        set affected [::vhdl_index::ownership::sequential_profile root]
        if {$head in {with identifier extended_identifier << ( string}} {
            set affected {variable_assignments sequential_signal_assignments}
            if {$head ni {with (}} {lappend affected sequential_procedure_calls sequential_actual_parameter_associations}
        }
        if {$issues eq {}} {
            lappend issues [diagnostic c UNRECOGNIZED_SEQUENTIAL_STATEMENT [list span $region found $head]]
        }
        ::vhdl_index::ownership::gap c sequential_statement $region $status $affected $owner $issues
        return {}
    }
    if {$modifier ne {}} {
        lappend issues [::vhdl_index::grammar::problem c ILLEGAL_MODIFIER [list span $modifier]]
    }
    lappend issues {*}[::vhdl_index::grammar::association_lexical c $region]
    if {[dict exists $fields diagnostics]} {lappend issues {*}[dict get $fields diagnostics]}
    return [dict merge $fields [dict create sequential_kind $family capability $capability owner_id $owner \
        span $region label [lindex $label 0] label_span [lindex $label 1] colon_span $colon \
        semicolon_span $semicolon status [expr {$issues eq {} ? "parsed" : "malformed"}] diagnostics $issues]]
}

proc ::vhdl_index::grammar::report_statement {state} {
    upvar 1 $state c
    set report [take c]
    set expression [concurrent_payload c {severity} MISSING_REPORT]
    set keyword {}
    set severity {}
    if {[kind c] eq "severity"} {
        set keyword [take c]
        set severity [concurrent_payload c {severity} MISSING_SEVERITY]
    }
    if {[kind c] eq "severity"} {reject c CLAUSE_ORDER}
    return [dict create report_keyword_span $report report_span $expression \
        severity_keyword_span $keyword severity_span $severity]
}

proc ::vhdl_index::grammar::wait_statement {state} {
    upvar 1 $state c
    set row [dict create wait_span [take c] on_span {} sensitivity_name_spans {} sensitivity_separator_spans {} \
        until_span {} condition_span {} for_span {} timeout_span {} diagnostics {}]
    set clauses {on until for}
    if {[kind c] eq "on"} {
        dict set row on_span [take c]
        set first $c(i)
        scan c $clauses {} {} {} 0 1
        set fence $c(grammarFence)
        set c(grammarFence) $c(i)
        set c(i) $first
        set names {}
        set separators {}
        set issues {}
        sensitivity_names c names separators issues
        set c(grammarFence) $fence
        dict set row sensitivity_name_spans $names
        dict set row sensitivity_separator_spans $separators
        dict set row diagnostics $issues
    }
    if {[kind c] eq "until"} {
        dict set row until_span [take c]
        dict set row condition_span [concurrent_payload c $clauses MISSING_CONDITION]
    }
    if {[kind c] eq "for"} {
        dict set row for_span [take c]
        dict set row timeout_span [concurrent_payload c $clauses MISSING_TIMEOUT]
    }
    if {[kind c] in $clauses} {reject c CLAUSE_ORDER}
    return $row
}

proc ::vhdl_index::grammar::sequential_call {state target actuals} {
    upvar 1 $state c
    set called [dict get $target span]
    if {$actuals ne {}} {
        set c(i) $actuals
        set called [extent c [lindex $called 0]]
    }
    set result [procedure_call c $called [dict get $target components] 0]
    dict set result called_name_status opaque
    if {$actuals ne {}} {
        dict set result diagnostics [dict get $result actual_parameters association_diagnostics]
    }
    return $result
}

proc ::vhdl_index::grammar::return_statement {state ownerKind} {
    upvar 1 $state c
    set keyword [take c]
    set value {}
    if {[kind c] ne "eof"} {
        set value [concurrent_payload c {} MISSING_EXPRESSION]
    }
    set code {}
    switch -- $ownerKind {
        function {
            if {$value eq {}} {set code RETURN_FUNCTION_MISSING_EXPRESSION}
        }
        procedure {
            if {$value ne {}} {set code RETURN_PROCEDURE_UNEXPECTED_EXPRESSION}
        }
        process {set code RETURN_OUTSIDE_SUBPROGRAM}
    }
    set issues {}
    if {$code ne {}} {lappend issues [diagnostic c $code [list span $keyword phase context]]}
    return [dict create return_span $keyword expression_span $value context_diagnostics $issues]
}

proc ::vhdl_index::grammar::loop_transfer {state head} {
    upvar 1 $state c
    set keyword [take c]
    set target {}
    if {[is_name [kind c] 0]} {set target [name_span c]}
    set when {}
    set condition {}
    if {[kind c] eq "when"} {
        set when [take c]
        set condition [concurrent_payload c {when} MISSING_CONDITION]
    }
    return [dict create ${head}_span $keyword loop_label_span $target when_span $when condition_span $condition]
}

proc ::vhdl_index::grammar::expression_assignment_value {state} {
    upvar 1 $state c
    if {[kind c] in {guarded unaffected after transport inertial reject force release}} {
        reject c ILLEGAL_MODIFIER [list found [kind c]]
    }
    set value [concurrent_payload c {when else ,} MISSING_EXPRESSION]
    return [list $value [dict create expression_span $value]]
}

proc ::vhdl_index::grammar::sequential_assignment {state target selection op} {
    upvar 1 $state c
    if {$target eq {}} {reject c MISSING_TARGET}
    validate_assignment_target c $target
    set operator [take c]
    lassign $selection with selector select matching
    if {$with ne {} && $c(edition) < 2008} {reject c EDITION_SEQUENTIAL_SELECTED [list span $with]}
    set delay {}
    set force {}
    set release {}
    set forceMode {}
    set valueGrammar expression_assignment_value
    set mode [kind c]
    if {$op eq "<="} {
        set valueGrammar waveform_value
        if {$mode eq "guarded"} {reject c ILLEGAL_MODIFIER [list found $mode]}
        if {$c(edition) < 2008 && $mode eq "identifier" &&
            [kind c 1] in {in out identifier extended_identifier number string character bit_string null}} {
            set spelling [string tolower [::vhdl_index::slice $c(snapshot) [span c]]]
            if {$spelling in {force release}} {reject c EDITION_SEQUENTIAL_FORCE_RELEASE}
        }
        if {$mode eq "force"} {
            set force [take c]
            set valueGrammar expression_assignment_value
        } elseif {$mode eq "release"} {
            set release [take c]
        } else {
            set delay [delay_mechanism c]
            if {[kind c] in {guarded force release transport inertial reject}} {
                reject c ILLEGAL_MODIFIER [list found [kind c]]
            }
        }
        if {($force ne {} || $release ne {}) && [kind c] in {in out}} {set forceMode [take c]}
    }
    if {$release ne {}} {
        if {$with ne {} || [kind c] ne "eof"} {reject c INVALID_RELEASE}
        set category simple
        set rows {}
    } elseif {$with ne {}} {
        set category selected
        set rows [selected_values c $valueGrammar 0]
    } else {
        lassign [conditional_values c $valueGrammar 0] category rows
        if {$category eq "conditional" && $c(edition) < 2008} {reject c EDITION_SEQUENTIAL_CONDITIONAL}
    }
    set expression {}
    set waveform {}
    if {$category eq "simple" && $rows ne {}} {
        set value [lindex $rows 0]
        if {[dict exists $value expression_span]} {set expression [dict get $value expression_span]}
        if {[dict exists $value waveform_span]} {set waveform [dict get $value waveform_span]}
    }
    return [dict create category $category target $target target_span [dict get $target span] \
        operator_span $operator delay $delay alternatives $rows expression_span $expression waveform_span $waveform \
        with_span $with selector_span $selector select_span $select matching_span $matching \
        force_span $force release_span $release force_mode_span $forceMode]
}
