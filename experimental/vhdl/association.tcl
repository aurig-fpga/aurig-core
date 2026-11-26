# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc ::vhdl_index::grammar::map_association {state form site keyword connector {context {}}} {
    upvar 1 $state c
    if {$context eq {}} {set context $form}
    set details [association_list c $context [expr {$site eq "concurrent_instantiation"}]]
    return [dict merge [dict create kind $form site $site \
        span [extent c [lindex $keyword 0]] keyword_span $keyword map_span $connector] $details]
}

# Association callers supply the enclosing grammar fence and diagnostic domain.
# Expression islands are scanned with the shared delimiter stack.
proc ::vhdl_index::grammar::association_list {state context statement} {
    upvar 1 $state c
    set open [require c ( EXPECTED_ASSOCIATION_OPEN]
    set contents [lindex $open 1]
    set separators {}
    set rows {}
    set issues {}
    set form list
    set special {}
    if {$context eq "formal_package" && $c(edition) == 2008 &&
        [kind c] in {<> default} && [kind c 1] eq ")"} {
        set form [expr {[kind c] eq "<>" ? "box" : "default"}]
        set special [take c]
    } else {
        # The outer parentheses count toward the same budget as a nested group.
        incr c(delimiters) -1
        set failed [catch {association_elements c $context $statement rows separators issues} result options]
        incr c(delimiters)
        if {$failed} {return -options $options $result}
    }
    set close [require c ) EXPECTED_ASSOCIATION_CLOSE]
    set inside [list $contents [lindex $close 0]]
    set group [list [lindex $open 0] [lindex $close 1]]
    return [dict create open_span $open close_span $close association_span $inside \
        association_content_span $inside association_group_span $group \
        association_status opaque association_form $form special_span $special associations $rows \
        separator_spans $separators association_validation [expr {$issues eq {} ? "parsed" : "malformed"}] \
        association_diagnostics $issues]
}

proc ::vhdl_index::grammar::association_elements {state context statement rowsVar separatorsVar issuesVar} {
    upvar 1 $state c $rowsVar rows $separatorsVar separators $issuesVar issues
    set named 0
    while {1} {
        set first $c(i)
        set start [lindex [span c] 0]
        set arrow {}
        set formal {}
        set actualFirst $first
        set actualStart $start
        set parts {}
        set allocator 0
        set issue {}
        while {[set next [kind c]] ni {, )}} {
            if {$next in {eof {;} begin end block process generate elsif when else generic port map entity component configuration} ||
                ($statement && (([is_name $next 0] && [kind c 1] eq ":") ||
                                $next in {assert postponed}))} {
                reject c EXPECTED_ASSOCIATION_CLOSE [list found $next]
            }
            if {$next eq "=>"} {
                if {$arrow ne {}} {
                    if {$issue eq {}} {set issue [problem c DUPLICATE_ARROW]}
                    incr c(i)
                    continue
                }
                if {$first == $c(i)} {
                    set issue [problem c MISSING_FORMAL]
                } elseif {$issue eq {}} {
                    set formal [extent c $start]
                    set issue [association_formal c $first]
                }
                set arrow [take c]
                set actualFirst $c(i)
                set actualStart [lindex [span c] 0]
                set parts {}
                set allocator 0
                set named 1
                continue
            }
            if {$issue eq {}} {
                set issue [association_token c $next [lindex $parts end] $context $allocator]
            }
            if {$next eq "new"} {set allocator 1}
            lappend parts $next
            if {$next in {( [ <<}} {
                if {$c(delimiters) == 0} {reject c DELIMITER_LIMIT}
                group c 0 $statement
            } else {
                incr c(i)
            }
        }
        if {$issue eq {}} {
            if {$first == $c(i)} {
                set code MISSING_ELEMENT
                if {$next eq ")" && $separators ne {}} {set code TRAILING_COMMA}
                set issue [problem c $code]
            } elseif {$actualFirst == $c(i)} {
                set issue [problem c MISSING_ACTUAL]
            } elseif {$arrow eq {} && $named} {
                set issue [problem c POSITIONAL_AFTER_NAMED [list span [extent c $start]]]
            } else {
                set issue [association_actual c $parts $context [extent c $actualStart]]
            }
        }
        if {$issue eq {}} {
            set actualKind opaque
            if {[lindex $parts 0] in {open inertial}} {set actualKind [lindex $parts 0]}
            set region [extent c $start]
            set lexical [association_lexical c $region]
            if {$lexical eq {}} {
                lappend rows [dict create span $region form [expr {$arrow eq {} ? "positional" : "named"}] \
                    formal_span $formal arrow_span $arrow actual_span [extent c $actualStart] actual_kind $actualKind]
            } else {
                lappend issues {*}$lexical
            }
        } else {
            lappend issues $issue
            if {$first < $c(i)} {lappend issues {*}[association_lexical c [extent c $start]]}
        }
        if {$next eq ")"} {return}
        lappend separators [take c]
    }
}

# Replay only the formal side with a local fence. This validates a name-shaped
# envelope, with opaque indexing, slicing and conversion arguments.
proc ::vhdl_index::grammar::association_formal {state first} {
    upvar 1 $state c
    set last $c(i)
    set fence $c(grammarFence)
    set c(grammarFence) $last
    set c(i) $first
    set failed [catch {
        name_span c 1
        while {[kind c] in {( . ' [}} {
            switch -- [kind c] {
                ( - {[} {group c}
                . {
                    incr c(i)
                    if {[kind c] eq "all"} {incr c(i)} else {designator c}
                }
                ' {
                    incr c(i)
                    if {[kind c] eq "range" || ([kind c] eq "subtype" && $c(edition) == 2008)} {
                        incr c(i)
                    } else {
                        name_span c
                    }
                }
            }
        }
        if {$c(i) != $last} {reject c INVALID_FORMAL}
    } issue options]
    set c(i) $last
    set c(grammarFence) $fence
    if {!$failed} {return {}}
    if {[dict get $options -errorcode] ne [list VHDL_INDEX $c(grammarDomain)]} {
        return -options $options $issue
    }
    return $issue
}

proc ::vhdl_index::grammar::association_token {state next previous context allocator} {
    upvar 1 $state c
    if {$next in {invalid unsupported ] >> : := | @ default <>}} {
        return [problem c INVALID_TOKEN [list found $next]]
    }
    if {$next eq "inertial" && $previous ne {}} {return [problem c INVALID_INERTIAL]}
    if {$next eq "range" && $previous ne "'" && [kind c 1] in {, )}} {return [problem c INCOMPLETE_ACTUAL]}
    if {$previous eq "=" && $next eq ">"} {return [problem c MALFORMED_ARROW]}
    if {$previous in {number string bit_string character null} && $next in {number string bit_string character null}} {
        return [problem c MISSING_SEPARATOR]
    }
    if {$previous in {identifier extended_identifier} && $next in {identifier extended_identifier} &&
        ($context eq "port" || $c(edition) < 2008) && !$allocator} {
        return [problem c MISSING_SEPARATOR]
    }
    if {$next eq "range" && $previous ne "'" && ($context eq "port" || $c(edition) < 2008) && !$allocator} {
        return [problem c SUBTYPE_ACTUAL_CONTEXT]
    }
    return {}
}

proc ::vhdl_index::grammar::association_actual {state parts context region} {
    upvar 1 $state c
    set first [lindex $parts 0]
    if {$first eq "inertial"} {
        if {$context ne "port"} {return [problem c INERTIAL_CONTEXT [list span $region]]}
        if {$c(edition) < 2008} {return [problem c EDITION_INERTIAL_ACTUAL [list span $region]]}
        set parts [lrange $parts 1 end]
    }
    if {$parts eq {}} {return [problem c MISSING_ACTUAL [list span $region]]}
    if {"open" in $parts && ($parts ne "open" || $first eq "inertial")} {
        return [problem c INVALID_OPEN [list span $region]]
    }
    if {[lindex $parts 0] ni {identifier extended_identifier number string bit_string character null open ( << new + - abs not ??} ||
        [lindex $parts end] ni {identifier extended_identifier number string bit_string character null open ( << [ range subtype all}} {
        return [problem c INCOMPLETE_ACTUAL [list span $region]]
    }
    return {}
}

# Formal sites may be indexed after a later map was parsed. Search the shared
# lexical evidence by offset so those callers need no mutable provenance cursor.
proc ::vhdl_index::grammar::association_lexical {state region} {
    upvar 1 $state c
    set issues $c(declarationLexical)
    if {$issues eq {}} {return {}}
    lassign $region start end
    set left 0
    set right [llength $issues]
    while {$left < $right} {
        set mid [expr {($left + $right) / 2}]
        if {[lindex [dict get [lindex $issues $mid] span] 0] < $start} {
            set left [expr {$mid + 1}]
        } else {
            set right $mid
        }
    }
    set found {}
    for {set i $left} {$i < [llength $issues]} {incr i} {
        set issue [lindex $issues $i]
        if {[lindex [dict get $issue span] 0] >= $end} {break}
        lappend found [dict merge $issue {phase lexical}]
    }
    return $found
}
