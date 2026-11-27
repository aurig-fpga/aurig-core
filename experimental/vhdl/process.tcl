# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc ::vhdl_index::parser::process_statement {state depth owner opening label colon postponed} {
    upvar 1 $state c
    set process [take c]
    set sensitivity {}
    if {[peek c] eq "("} {
        set c(grammarFence) [llength $c(significant)]
        set c(grammarDomain) PROCESS_SENSITIVITY
        set failed [catch {::vhdl_index::grammar::process_sensitivity c} sensitivity options]
        if {$failed} {
            if {[dict get $options -errorcode] eq {VHDL_INDEX PROCESS_SENSITIVITY}} {
                return -code error -errorcode {VHDL_INDEX STRUCTURE} $sensitivity
            }
            return -options $options $sensitivity
        }
    }
    set is {}
    if {[peek c] eq "is"} {set is [take c]}
    set syntax [dict create label [lindex $label 0] label_span [lindex $label 1] colon_span $colon \
        postponed_span $postponed process_span $process is_span $is sensitivity $sensitivity \
        header_span [::vhdl_index::grammar::extent c $opening]]
    sequential_scope c process $label $depth [list $opening $owner] {} {} $syntax
}

# The existing typed terminator has already consumed and checked these
# tokens. Record their spans without walking the sequential body again.
proc ::vhdl_index::parser::process_closing {state syntax endOrdinal tail begin} {
    upvar 1 $state c
    set after $c(i)
    set semicolon [span c previous]
    set closing [scope_closing c $tail $begin]
    set c(i) $endOrdinal
    set end [take c]
    set postponed {}
    if {[peek c] eq "postponed"} {set postponed [take c]}
    set process [span c]
    set c(i) $after
    if {$postponed ne {} && [dict get $syntax postponed_span] eq {}} {
        lappend c(diagnostics) [diagnostic c PROCESS_UNEXPECTED_END_POSTPONED [list span $postponed]]
    }
    return [dict create terminator_span $tail end_name_span [dict get $closing end_name_span] \
        begin_span $begin sequential_span [dict get $closing concurrent_span] sequential_status opaque \
        end_span $end end_postponed_span $postponed end_process_span $process semicolon_span $semicolon]
}

proc ::vhdl_index::parser::publish_process {state syntax parent} {
    upvar 1 $state c
    lappend c(concurrentStatements) $syntax
    set sensitivity [dict get $syntax sensitivity]
    if {$sensitivity ne {} && [dict get $sensitivity status] ne "parsed"} {
        ::vhdl_index::ownership::gap c process_sensitivity [dict get $sensitivity span] malformed \
            {sensitivity_lists} $parent [dict get $sensitivity diagnostics]
    }
}

proc ::vhdl_index::grammar::process_sensitivity {state} {
    upvar 1 $state c
    set first $c(i)
    set open [span c]
    set failed [catch {group c 0 2} region options]
    if {$failed} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX PROCESS_SENSITIVITY} ||
            [dict get $region code] ne "PROCESS_SENSITIVITY_UNCLOSED_GROUP" || [peek c] ne "begin"} {
            return -options $options $region
        }
        # BEGIN cannot be part of a sensitivity name. The typed walker still
        # has to prove the process ending before the header can be published.
        set end [lindex [span c] 0]
        return [dict create kind list span [list [lindex $open 0] $end] \
            open_span $open close_span {} content_span [list [lindex $open 1] $end] \
            all_span {} name_spans {} separator_spans {} status malformed diagnostics [list $region]]
    }
    set after $c(i)
    set close [span c previous]
    set fence $c(grammarFence)
    set c(i) [expr {$first + 1}]
    set c(grammarFence) [expr {$after - 1}]
    set form list
    set all {}
    set issues {}
    set names {}
    set commas {}
    if {[kind c] eq "all"} {
        set form all
        set all [take c]
        if {$c(edition) < 2008} {
            lappend issues [problem c EDITION_PROCESS_ALL [list span $all]]
        }
        if {[kind c] ne "eof"} {lappend issues [problem c INVALID_ALL]}
    } else {
        sensitivity_names c names commas issues
    }
    set c(i) $after
    set c(grammarFence) $fence
    lappend issues {*}[association_lexical c $region]
    return [dict create kind $form span $region open_span $open close_span $close \
        content_span [list [lindex $open 1] [lindex $close 0]] all_span $all name_spans $names \
        separator_spans $commas status [expr {$issues eq {} ? "parsed" : "malformed"}] diagnostics $issues]
}

proc ::vhdl_index::grammar::sensitivity_names {state namesVar commasVar issuesVar} {
    upvar 1 $state c $namesVar names $commasVar commas $issuesVar issues
    set fence $c(grammarFence)
    while {1} {
        set first $c(i)
        set marker [scan c {, )} {} {} {} 0 1]
        set last $c(i)
        set c(i) $first
        set c(grammarFence) $last
        set failed [catch {
            if {$first == $last} {reject c MISSING_NAME}
            if {[kind c] eq "("} {reject c EXPECTED_NAME}
            set name [assignment_target c]
            if {[kind c] ne "eof"} {reject c INVALID_NAME_SUFFIX}
            foreach suffix [dict get $name suffixes] {
                if {[dict exists $suffix empty] && [dict get $suffix empty]} {reject c EMPTY_NAME_SUFFIX}
            }
            dict get $name span
        } item options]
        set c(i) $last
        set c(grammarFence) $fence
        if {$failed} {
            if {[dict get $options -errorcode] ne [list VHDL_INDEX $c(grammarDomain)]} {
                return -options $options $item
            }
            lappend issues $item
        } else {
            lappend names $item
        }
        if {$marker ne ","} {return}
        lappend commas [take c]
    }
}
