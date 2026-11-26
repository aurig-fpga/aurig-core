# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc ::vhdl_index::parser::concurrent_leaf {state owner ownerKind opening label} {
    upvar 1 $state c
    set first $c(i)
    set colon {}
    if {$label ne {}} {set colon [span c previous]}
    set postponed {}
    if {[peek c] eq "postponed"} {set postponed [take c]}
    if {[peek c] eq "assert"} {
        set head [dict create label [lindex $label 0] label_span [lindex $label 1] \
            colon_span $colon postponed_span $postponed]
        parse_concurrent c $owner $ownerKind $opening $head ASSERTION concurrent_assertion \
            {concurrent_assertions} ::vhdl_index::grammar::assertion
        return
    }
    set c(i) $first
    instance_leaf c $owner $ownerKind $opening $label
}

# Index one bounded production. On a local error the same cursor either
# reaches a proved sibling boundary or lets the enclosing transaction unwind.
proc ::vhdl_index::parser::parse_concurrent {state owner ownerKind opening head domain form capabilities production args} {
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
        recover_concurrent c $ownerKind
        concurrent_candidate c $owner $opening malformed $issue [list $form] $capabilities
        return
    }
    set lexical [::vhdl_index::grammar::association_lexical c $region]
    if {$lexical ne {}} {
        concurrent_candidate c $owner $opening malformed [lindex $lexical 0] [list $form] $capabilities
        return
    }
    lappend c(concurrentStatements) [dict merge $head $row [dict create span $region \
        terminator_span $tail owner_id $owner capability [lindex $capabilities 0] \
        status parsed diagnostics {} expression_status opaque]]
}

proc ::vhdl_index::parser::recover_concurrent {state ownerKind} {
    upvar 1 $state c
    # Mode 2 stops at a sibling even when recovery starts at its first token.
    set ends {end elsif}
    if {$ownerKind eq "generate"} {lappend ends else when}
    set marker [scan c [concat {{;} begin =>} $ends] {} {} {begin end} 2]
    if {$marker eq ";"} {incr c(i); return}
    if {$marker in $ends || $marker eq "concurrent_candidate"} {return}
    fail c UNPROVEN_CONCURRENT_BOUNDARY [list found [peek c]]
}

# Payload connectors are considered only at depth zero. Delimiter tracking
# is shared with scopes, and literals are single significant tokens.
proc ::vhdl_index::grammar::concurrent_payload {state stops missing} {
    upvar 1 $state c
    set first $c(i)
    set start [lindex [span c] 0]
    set marker [scan c [concat $stops {{;} end begin elsif => := :}] {} {} {begin end} 2]
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
