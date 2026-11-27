# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc ::vhdl_index::parser::sequential_control {state depth kind name matching} {
    upvar 1 $state c
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
            sequential_statement c $depth
        }
    }
    return [terminator c $kind $name 1 $matching]
}

# Walk each direct statement once for boundaries. Nested statements use the
# same walker with no publication target.
proc ::vhdl_index::parser::sequential_statement {state depth {owner {}} {ownerKind {}} {rowsVar {}}} {
    upvar 1 $state c
    if {$rowsVar ne {}} {upvar 1 $rowsVar rows}
    set start [lindex [span c] 0]
    set label [optional_label c]
    set colon {}
    if {$label ne {}} {set colon [span c previous]}
    set head [peek c]
    switch -- $head {
        if - case - for - while - loop {
            set opener [take c]
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
            set firstIssue [llength $c(diagnostics)]
            set tail [sequential_control c [descend c $depth] $kind $label [expr {$matching ne {}}]]
            if {$owner ne {}} {
                set region [list $start [lindex $tail 1]]
                set issues [lrange $c(diagnostics) $firstIssue end]
                set status [expr {$issues eq {} ? "parsed" : "malformed"}]
                dict lappend rows control_flow_envelopes [dict create sequential_kind sequential_control_envelope \
                    kind $kind span $region owner_id $owner label_span [lindex $label 1] colon_span $colon \
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
            set row [sequential_leaf c $owner $ownerKind $start $label $colon $head]
            if {$row ne {}} {dict lappend rows [dict get $row capability] $row}
        }
    }
}

proc ::vhdl_index::parser::sequential_leaf {state owner ownerKind start label colon head} {
    upvar 1 $state c
    set first $c(i)
    set modifier {}
    if {$head eq "postponed"} {
        set modifier [take c]
        set head [peek c]
    }
    set body $c(i)
    set marker [scan c {{;} end begin elsif =>} {} {} {begin end} 0 0 $head]
    set fence $c(i)
    if {$marker eq "eof"} {fail c TRUNCATED_SCOPE}
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
            identifier - extended_identifier - << {
                set c(grammarDomain) SEQUENTIAL_CALL
                set target [::vhdl_index::grammar::assignment_target c actuals]
                if {[::vhdl_index::grammar::kind c] ne "eof"} {
                    dict create
                } else {
                    set family sequential_procedure_call
                    set capability sequential_procedure_calls
                    ::vhdl_index::grammar::sequential_call c $target $actuals
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
        set fields {}
    }
    if {$family eq {}} {return {}}
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
