# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Opt in after loading frontend.tcl. The ordinary frontend never loads this module.
namespace eval ::vhdl_index::bounded {
    namespace path {::vhdl_index::grammar ::vhdl_index::parser}
    variable logical {and or nand nor xor xnor}
    variable relations {= /= < <= > >= ?= ?/= ?< ?<= ?> ?>=}
}

source [file join [file dirname [info script]] bounded_names.tcl]

proc ::vhdl_index::bounded::read {path edition {requestedLimits {}}} {
    variable ::vhdl_index::sourceSerial
    check_edition $edition
    set limits [::vhdl_index::limits $requestedLimits]
    set decoded [::aurig::core::util::read_vhdl_source $path]
    set snapshot [::vhdl_index::snapshot [list [file normalize $path] [incr sourceSerial]] $decoded]
    return [dict create snapshot $snapshot tape [::vhdl_index::lexer::lex $snapshot $edition $limits] limits $limits]
}

proc ::vhdl_index::bounded::check_edition {edition} {
    if {$edition ni {1993 2002 2008}} {error "Unknown bounded grammar edition: $edition"}
}

# Convert a normalized source extent to an interval of significant ordinals.
# Trivia is ignored and a boundary in the middle of a token is rejected.
proc ::vhdl_index::bounded::interval {tape extent} {
    lassign $extent start end
    set starts [dict get $tape starts]
    set significant [dict get $tape significant]
    set length [lindex $starts end]
    if {$start < 0 || $end < $start || $end > $length} {error "Invalid source extent: $extent"}
    set result {}
    foreach offset $extent {
        set low 0
        set high [expr {[llength $significant] - 1}]
        while {$low < $high} {
            set mid [expr {($low + $high) / 2}]
            if {[lindex $starts [lindex $significant $mid]] < $offset} {
                set low [expr {$mid + 1}]
            } else {
                set high $mid
            }
        }
        if {$low > 0} {
            set previous [lindex $significant [expr {$low - 1}]]
            if {[lindex $starts [expr {$previous + 1}]] > $offset} {
                error "Extent divides a significant token: $extent"
            }
        }
        lappend result $low
    }
    return $result
}

proc ::vhdl_index::bounded::parse {snapshot tape edition entry first last {requestedLimits {}}} {
    check_edition $edition
    if {$entry ni {expression name discrete_range}} {error "Unknown bounded grammar entry: $entry"}
    set limits {depth 32 nodes 100000}
    dict for {key value} $requestedLimits {
        if {![dict exists $limits $key] || ![string is integer -strict $value] ||
            $value < 1 || $value > [dict get $limits $key]} {
            error "Invalid bounded grammar limit $key=$value"
        }
        dict set limits $key $value
    }
    set significant [dict get $tape significant]
    if {![string is integer -strict $first] || ![string is integer -strict $last] ||
        $first < 0 || $last < $first || $last >= [llength $significant]} {
        error "Invalid significant-token interval: $first $last"
    }
    array set c [list snapshot $snapshot edition $edition labels $::vhdl_index::lexer::labels \
        i $first grammarFence $last grammarDomain BOUNDED rows {} ambiguity 0 \
        depth 0 depthLimit [dict get $limits depth] nodeLimit [dict get $limits nodes] \
        declarationLexical [dict get $tape diagnostics]]
    foreach key {starts kinds significant} {set c($key) [dict get $tape $key]}
    set start [lindex [span c] 0]
    set end $start
    if {$last > $first} {
        set c(i) $last
        set end [lindex [span c previous] 1]
        set c(i) $first
    }
    set c(fenceOffset) $end
    set extent [list $start $end]
    set result [dict create source_id [dict get $snapshot id] token_interval [list $first $last] \
        span $extent entry $entry edition $edition]
    set lexical [association_lexical c $extent]
    if {$lexical ne {}} {
        set status malformed
        foreach issue $lexical {
            if {[dict get $issue code] eq "TOKEN_LIMIT"} {
                set status unavailable
                break
            }
            if {[dict get $issue code] eq "UNSUPPORTED_DIRECTIVE"} {set status unsupported}
        }
        return [dict merge $result [failure $status $lexical $extent]]
    }
    set failed [catch {
        switch -- $entry {
            expression {set root [expression c]}
            name {set root [name c name]}
            discrete_range {set root [discrete c [simple c]]}
        }
        if {[kind c] ne "eof"} {stop c malformed TRAILING_TOKEN}
    } issue options]
    if {$failed} {
        set code [dict get $options -errorcode]
        if {$code eq {VHDL_INDEX BOUNDED}} {
            lassign [dict get $issue span] issueStart issueEnd
            if {$issueStart < $start || $issueEnd > $end} {
                dict set issue span [current_extent c]
            }
            set status malformed
        } elseif {[lrange $code 0 1] eq {VHDL_INDEX BOUNDED_RESULT}} {
            set status [lindex $code 2]
        } else {
            return -options $options $issue
        }
        return [dict merge $result [failure $status [list $issue] $extent]]
    }
    return [dict merge $result [dict create status [expr {$c(ambiguity) ? "ambiguous" : "parsed"}] \
        complete 1 root $root rows $c(rows) diagnostics {} unresolved {}]]
}

proc ::vhdl_index::bounded::failure {status diagnostics extent} {
    return [dict create status $status complete 0 root {} rows {} diagnostics $diagnostics unresolved [list $extent]]
}

proc ::vhdl_index::bounded::current_extent {state} {
    upvar 1 $state c
    if {$c(i) >= $c(grammarFence)} {return [list $c(fenceOffset) $c(fenceOffset)]}
    return [span c]
}

proc ::vhdl_index::bounded::stop {state status code {extent {}}} {
    upvar 1 $state c
    if {$extent eq {}} {set extent [current_extent c]}
    return -code error -errorcode [list VHDL_INDEX BOUNDED_RESULT $status] \
        [dict create code BOUNDED_$code severity error span $extent]
}

proc ::vhdl_index::bounded::enter {state} {
    upvar 1 $state c
    if {$c(depth) >= $c(depthLimit)} {stop c unavailable DEPTH_LIMIT}
    incr c(depth)
}

proc ::vhdl_index::bounded::add {state type start end {children {}} {connectors {}} {candidates {}}} {
    upvar 1 $state c
    set id [llength $c(rows)]
    if {$id >= $c(nodeLimit)} {stop c unavailable NODE_LIMIT}
    if {[llength $candidates] > 1} {set c(ambiguity) 1}
    lappend c(rows) [list $type $start $end $children $connectors $candidates]
    return $id
}

proc ::vhdl_index::bounded::node {result id} {
    if {![string is integer -strict $id] || $id < 0 || $id >= [llength [dict get $result rows]]} {
        error "Unknown bounded grammar node: $id"
    }
    lassign [lindex [dict get $result rows] $id] type start end children connectors candidates
    return [dict create kind $type span [list $start $end] children $children \
        connectors $connectors candidates $candidates complete 1 \
        identity [list [dict get $result source_id] [dict get $result token_interval] \
            [dict get $result entry] $id]]
}

proc ::vhdl_index::bounded::token {state} {
    upvar 1 $state c
    set label [kind c]
    return [linsert [take c] 0 $label]
}

proc ::vhdl_index::bounded::need {state label code} {
    upvar 1 $state c
    if {[kind c] ne $label} {stop c malformed $code}
    return [token c]
}

proc ::vhdl_index::bounded::close_group {state label} {
    upvar 1 $state c
    set close [need c $label EXPECTED_CLOSE]
    incr c(depth) -1
    return $close
}

proc ::vhdl_index::bounded::leaf {state type} {
    upvar 1 $state c
    lassign [take c] start end
    return [add c $type $start $end]
}

proc ::vhdl_index::bounded::unary {state type operator operand} {
    upvar 1 $state c
    if {[lindex $c(rows) $operand 0] eq "reduction"} {
        stop c unsupported REDUCTION_GROUPING [lrange $operator 1 2]
    }
    return [add c $type [lindex $operator 1] [lindex $c(rows) $operand 2] [list $operand] [list $operator]]
}

proc ::vhdl_index::bounded::binary {state type operator left right} {
    upvar 1 $state c
    if {[lindex $c(rows) $left 0] eq "reduction" || [lindex $c(rows) $right 0] eq "reduction"} {
        stop c unsupported REDUCTION_GROUPING [lrange $operator 1 2]
    }
    return [add c $type [lindex $c(rows) $left 1] [lindex $c(rows) $right 2] \
        [list $left $right] [list $operator]]
}

proc ::vhdl_index::bounded::expression {state} {
    upvar 1 $state c
    variable logical
    if {[kind c] eq "??"} {
        set result [unary c condition [token c] [primary c]]
        if {[kind c] in {** * / mod rem + - & sll srl sla sra rol ror = /= < <= > >= ?= ?/= ?< ?<= ?> ?>= and or xor xnor nand nor}} {
            stop c malformed CONDITION_GROUPING
        }
        return $result
    }
    set left [relation c]
    set family [kind c]
    if {$family ni $logical} {return $left}
    while {[kind c] eq $family} {
        set operator [token c]
        set left [binary c logical $operator $left [relation c]]
        if {$family in {nand nor}} {break}
    }
    if {[kind c] in $logical} {stop c malformed LOGICAL_CHAIN}
    return $left
}

proc ::vhdl_index::bounded::relation {state} {
    upvar 1 $state c
    variable relations
    set left [shift c]
    if {[kind c] in $relations} {
        set operator [token c]
        set left [binary c relation $operator $left [shift c]]
        if {[kind c] in $relations} {stop c malformed RELATIONAL_CHAIN}
    }
    return $left
}

proc ::vhdl_index::bounded::shift {state} {
    upvar 1 $state c
    set shifts {sll srl sla sra rol ror}
    set left [simple c]
    if {[kind c] in $shifts} {
        set operator [token c]
        set left [binary c shift $operator $left [simple c]]
        if {[kind c] in $shifts} {stop c malformed SHIFT_CHAIN}
    }
    return $left
}

proc ::vhdl_index::bounded::simple {state} {
    upvar 1 $state c
    set sign {}
    if {[kind c] in {+ -}} {set sign [token c]}
    set left [term c]
    if {$sign ne {}} {set left [unary c sign $sign $left]}
    while {[kind c] in {+ - &}} {
        set operator [token c]
        set left [binary c binary $operator $left [term c]]
    }
    return $left
}

proc ::vhdl_index::bounded::term {state} {
    upvar 1 $state c
    set left [factor c]
    while {[kind c] in {* / mod rem}} {
        set operator [token c]
        set left [binary c binary $operator $left [factor c]]
    }
    return $left
}

proc ::vhdl_index::bounded::factor {state} {
    upvar 1 $state c
    variable logical
    set next [kind c]
    if {$next in {abs not}} {return [unary c unary [token c] [primary c]]}
    if {$c(edition) == 2008 && $next in $logical} {
        return [unary c reduction [token c] [primary c]]
    }
    set left [primary c]
    if {[kind c] eq "**"} {
        set result [binary c binary [token c] $left [primary c]]
        if {[kind c] eq "**"} {stop c malformed EXPONENT_CHAIN}
        return $result
    }
    return $left
}

proc ::vhdl_index::bounded::primary {state} {
    upvar 1 $state c
    switch -- [kind c] {
        number {
            set magnitude [leaf c number]
            if {![is_name [kind c] 0]} {return $magnitude}
            set unit [name c unit]
            return [add c physical [lindex $c(rows) $magnitude 1] [lindex $c(rows) $unit 2] \
                [list $magnitude $unit]]
        }
        bit_string - null {return [leaf c [kind c]]}
        identifier - extended_identifier - string - character - << {return [name c primary]}
        ( {return [grouped_primary c]}
        new {return [allocator c]}
        default {stop c malformed EXPECTED_PRIMARY}
    }
}

# A single positional element is a group. A comma or choice arrow proves an
# aggregate. Named choices use simple expressions or discrete ranges.
proc ::vhdl_index::bounded::grouped_primary {state} {
    upvar 1 $state c
    enter c
    set open [token c]
    set slots {}
    set separators [list $open]
    set named 0
    set seenOthers 0
    while {1} {
        if {$seenOthers} {stop c malformed OTHERS_NOT_FINAL}
        set first [lindex [current_extent c] 0]
        if {[kind c] eq "others"} {
            set value [leaf c others]
        } else {
            set value [expression c]
        }
        set arrow {}
        set choices {}
        set bars {}
        if {[kind c] in {=> |} || [range_shape c $value] || [lindex $c(rows) $value 0] eq "others"} {
            while {1} {
                set choice [choice c $value]
                if {[lindex $c(rows) $choice 0] eq "others"} {set seenOthers 1}
                lappend choices $choice
                if {[kind c] ne "|"} {break}
                if {$seenOthers} {stop c malformed OTHERS_NOT_ALONE}
                lappend bars [token c]
                if {[kind c] eq "others"} {stop c malformed OTHERS_NOT_ALONE}
                set value [expression c]
            }
            set arrow [need c => EXPECTED_CHOICE_ARROW]
            set value [expression c]
        }
        if {$slots eq {} && $arrow eq {} && [kind c] eq ")"} {
            set close [close_group c )]
            return [add c group [lindex $open 1] [lindex $close 2] [list $value] [list $open $close]]
        }
        if {[::vhdl_index::grammar::association_order named [expr {$arrow ne {}}]]} {
            stop c malformed POSITIONAL_AFTER_NAMED
        }
        set connectors {}
        if {$arrow ne {}} {set connectors [linsert $bars end $arrow]}
        lappend slots [add c element $first [lindex $c(rows) $value 2] [linsert $choices end $value] $connectors]
        if {[kind c] ne ","} {break}
        lappend separators [token c]
    }
    set close [close_group c )]
    return [add c aggregate [lindex $open 1] [lindex $close 2] $slots [linsert $separators end $close]]
}

proc ::vhdl_index::bounded::choice {state value} {
    upvar 1 $state c
    set type [lindex $c(rows) $value 0]
    if {$type eq "others"} {return $value}
    if {$type in {relation shift logical condition reduction}} {stop c malformed EXPECTED_SIMPLE_CHOICE}
    if {[range_shape c $value]} {return [discrete c $value]}
    set candidates {}
    if {$type in {identifier extended_identifier}} {set candidates {simple_expression element_simple_name discrete_subtype}}
    return [add c choice [lindex $c(rows) $value 1] [lindex $c(rows) $value 2] [list $value] {} $candidates]
}
