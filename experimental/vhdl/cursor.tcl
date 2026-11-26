namespace eval ::vhdl_index::parser {}

# The cursor is a significant-token ordinal. Only this module accesses the tape
# layout, including the hot delimiter scan through opaque regions.
proc ::vhdl_index::parser::peek {state {ahead 0}} {
    upvar 1 $state c
    set idx [lindex $c(significant) [expr {$c(i) + $ahead}]]
    if {$idx eq {}} {return eof}
    return [lindex $c(labels) [lindex $c(kinds) $idx]]
}

proc ::vhdl_index::parser::span {state {which current}} {
    upvar 1 $state c
    set at $c(i)
    if {$which eq "previous"} {incr at -1}
    set idx [lindex $c(significant) $at]
    set start [lindex $c(starts) $idx]
    set end [lindex $c(starts) [expr {$idx + 1}]]
    if {$end eq {}} {set end $start}
    return [list $start $end]
}

proc ::vhdl_index::parser::take {state} {
    upvar 1 $state c
    set extent [span c]
    incr c(i)
    return $extent
}

proc ::vhdl_index::parser::accept {state kind} {
    upvar 1 $state c
    if {[peek c] ne $kind} {return 0}
    incr c(i)
    return 1
}

proc ::vhdl_index::parser::expect {state kind} {
    upvar 1 $state c
    if {![accept c $kind]} {fail c EXPECTED_TOKEN [list expected $kind found [peek c]]}
}

proc ::vhdl_index::parser::diagnostic {state code details} {
    upvar 1 $state c
    return [dict merge [dict create code $code severity error span [span c]] $details]
}

proc ::vhdl_index::parser::fail {state code {details {}}} {
    upvar 1 $state c
    return -code error -errorcode {VHDL_INDEX STRUCTURE} [diagnostic c $code $details]
}

proc ::vhdl_index::parser::is_name {kind operator} {
    return [expr {$kind in {identifier extended_identifier} || ($operator && $kind eq "string")}]
}

proc ::vhdl_index::parser::read_name {state {designator 0}} {
    upvar 1 $state c
    set kind [peek c]
    if {![is_name $kind $designator]} {
        fail c EXPECTED_NAME [list found $kind]
    }
    set extent [take c]
    set spelling [::vhdl_index::slice $c(snapshot) $extent]
    if {$kind eq "extended_identifier"} {
        set key $spelling
    } elseif {$kind eq "string"} {
        set key [string tolower [string range $spelling 1 end-1]]
    } else {
        set key [string tolower $spelling]
    }
    return [list $spelling $extent $key]
}

# Advance to a stop at delimiter depth zero. Absolute character positions are
# obtained only on a diagnostic or when materializing a completed record.
proc ::vhdl_index::parser::scan {state stops {groupMode {}} {declarationContext {}} {hardStops {}} {concurrent 0}} {
    upvar 1 $state c
    set stopIds {0 8}
    foreach stop $stops {lappend stopIds [dict get $c(symbols) $stop]}
    set hardIds {}
    foreach stop $hardStops {lappend hardIds [dict get $c(symbols) $stop]}
    set depthLimit $c(delimiters)
    set stack {}
    set significant $c(significant)
    set kinds $c(kinds)
    set pairs $c(pairs)
    set closers $c(closers)
    set triggers $c(unitTriggers)
    set package [dict get $c(symbols) package]
    set body [dict get $c(symbols) body]
    set pos $c(i)
    if {$concurrent} {
        set scanStart $pos
        set colon [dict get $c(symbols) :]
        set concurrentStops {}
        foreach word {entity component configuration generic port for if case assert postponed} {
            lappend concurrentStops [dict get $c(symbols) $word]
        }
    }
    if {$declarationContext ne {}} {
        set c(opaqueBoundary) {}
        set declarationKinds $c(declarationKinds)
        set firstCandidate [expr {$pos + ($declarationContext ni {opaque_tail subprogram_header})}]
    }
    set grouped [expr {$groupMode ne {}}]
    if {$grouped} {
        set k [lindex $kinds [lindex $significant $pos]]
        set stack [list [dict get $pairs $k]]
        set fence $c(grammarFence)
        set strict [expr {$groupMode eq "strict"}]
        set hard [list 0 [dict get $c(symbols) end] [dict get $c(symbols) begin]]
        set invalid [list 7 8 [dict get $c(symbols) {;}]]
        incr pos
        if {$strict && $pos < $fence && [lindex $c(labels) $k] eq "(" &&
            [lindex $kinds [lindex $significant $pos]] == [lindex $stack 0]} {
            set c(i) $pos
            ::vhdl_index::grammar::reject c EMPTY_GROUP
        }
    }
    while {1} {
        set k [lindex $kinds [lindex $significant $pos]]
        if {$grouped} {
            if {$pos >= $fence || $k in $hard} {
                set c(i) $pos
                ::vhdl_index::grammar::reject c UNCLOSED_GROUP
            }
            if {$strict && $k in $invalid} {
                set c(i) $pos
                ::vhdl_index::grammar::reject c INVALID_GROUP_TOKEN [list found [lindex $c(labels) $k]]
            }
        } elseif {$k == 0 || $k == 8 || ($stack eq {} && $k in $stopIds) || $k in $hardIds} {
            set c(i) $pos
            if {$stack ne {}} {fail c UNCLOSED_DELIMITER}
            if {$k == 8} {fail c UNSUPPORTED_TOKEN}
            return [lindex $c(labels) $k]
        }
        if {$concurrent && $pos > $scanStart && $stack eq {} &&
            ($k in $concurrentStops ||
             ($k in {1 2} && [lindex $kinds [lindex $significant [expr {$pos + 1}]]] == $colon))} {
            set c(i) $pos
            return concurrent_candidate
        }
        if {[dict exists $pairs $k]} {
            if {[llength $stack] >= $depthLimit} {
                set c(i) $pos
                if {$grouped} {::vhdl_index::grammar::reject c DELIMITER_LIMIT}
                fail c DELIMITER_LIMIT
            }
            lappend stack [dict get $pairs $k]
        } elseif {$k in $closers} {
            if {$stack eq {} || $k != [lindex $stack end]} {
                set c(i) $pos
                if {$grouped} {::vhdl_index::grammar::reject c MISMATCHED_DELIMITER}
                fail c UNMATCHED_DELIMITER
            }
            set stack [lreplace $stack end end]
            if {$grouped && $stack eq {}} {
                set c(i) [expr {$pos + 1}]
                return
            }
        } elseif {$stack eq {} && [dict exists $triggers $k]} {
            set next [expr {$pos + 1}]
            set name [lindex $kinds [lindex $significant $next]]
            if {$k == $package && $name == $body} {
                incr next
                set name [lindex $kinds [lindex $significant $next]]
            }
            if {$name in {1 2} &&
                [lindex $kinds [lindex $significant [expr {$next + 1}]]] eq [dict get $triggers $k]} {
                set c(i) $pos
                fail c UNSAFE_UNIT_BOUNDARY [list found [lindex $c(labels) $k]]
            }
        } elseif {$declarationContext ne {} && $stack eq {} && [dict exists $declarationKinds $k] &&
            $pos >= $firstCandidate && $c(opaqueBoundary) eq {}} {
            set c(i) $pos
            set certainty [::vhdl_index::grammar::declaration_start c $declarationContext]
            if {$certainty eq "safe" && ($declarationContext in {object indexed_item attribute_item configuration_specification} ||
                ($declarationContext eq "subprogram_header" && [dict get $declarationKinds $k] eq "subprogram"))} {
                return declaration
            }
            if {$certainty eq "safe" || ($certainty eq "uncertain" && $declarationContext in {object indexed_item attribute_item configuration_specification})} {
                set c(opaqueBoundary) [span c]
            }
        }
        incr pos
    }
}
