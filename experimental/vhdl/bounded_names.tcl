# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc ::vhdl_index::bounded::designator_node {state {mode name}} {
    upvar 1 $state c
    set next [kind c]
    if {$mode in {mark unit}} {
        lassign [name_span c] start end
        return [add c $next $start $end]
    }
    lassign [designator c] extent type
    lassign $extent start end
    return [add c $type $start $end]
}

proc ::vhdl_index::bounded::name {state mode} {
    upvar 1 $state c
    set next [kind c]
    if {$next eq "<<" && $mode ni {mark unit}} {
        set prefix [external c]
    } elseif {$mode eq "primary" && $next in {string character} &&
        [kind c 1] ni {. ( ' {[}}} {
        if {$next eq "string"} {
            set span [take c]
            lassign $span start end
            set candidates {}
            if {[operator_problem c $span] eq {}} {set candidates {string_literal operator_symbol}}
            return [add c string $start $end {} {} $candidates]
        }
        return [leaf c character_literal]
    } else {
        set prefix [designator_node c $mode]
    }

    while {1} {
        set next [kind c]
        if {$next eq "."} {
            set dot [token c]
            if {[kind c] eq "all" && $mode ni {mark unit}} {
                set suffix [leaf c all]
            } else {
                set suffix [designator_node c $mode]
            }
            set type [lindex $c(rows) $suffix 0]
            switch -- $type {
                all {set form dereference}
                operator {set form selected_operator}
                character {set form selected_character}
                default {set form selected}
            }
            set prefix [add c $form [lindex $c(rows) $prefix 1] [lindex $c(rows) $suffix 2] \
                [list $prefix $suffix] [list $dot]]
        } elseif {$mode eq "unit"} {
            return $prefix
        } elseif {$mode eq "mark" && !($next eq "'" && $c(edition) == 2008 && [kind c 1] eq "subtype")} {
            return $prefix
        } elseif {$next eq "'"} {
            set tick [token c]
            if {[kind c] eq "("} {
                if {$mode ne "primary" || ![is_type_mark c $prefix]} {stop c malformed UNEXPECTED_QUALIFICATION}
                return [qualification c $prefix $tick]
            }
            set prefix [attribute c $prefix $tick]
        } elseif {$next eq "\["} {
            set prefix [signature_prefix c $prefix]
        } elseif {$next eq "("} {
            set prefix [name_group c $prefix $mode]
        } else {
            return $prefix
        }
    }
}

proc ::vhdl_index::bounded::is_type_mark {state id} {
    upvar 1 $state c
    return [expr {[lindex $c(rows) $id 0] in {identifier extended_identifier selected subtype_attribute}}]
}

proc ::vhdl_index::bounded::attribute {state prefix tick} {
    upvar 1 $state c
    set next [kind c]
    set type attribute
    if {[is_range_attribute c]} {
        set type range_attribute
        set designator [leaf c $next]
    } elseif {$next eq "subtype" && $c(edition) == 2008} {
        set type subtype_attribute
        set designator [leaf c subtype]
    } else {
        lassign [name_span c] start end
        set designator [add c $next $start $end]
    }
    return [add c $type [lindex $c(rows) $prefix 1] [lindex $c(rows) $designator 2] \
        [list $prefix $designator] [list $tick]]
}

proc ::vhdl_index::bounded::signature_prefix {state prefix} {
    upvar 1 $state c
    set signature [signature c]
    set marks {}
    foreach extent [dict get $signature type_mark_spans] {
        lassign $extent start end
        lappend marks [add c type_mark $start $end]
    }
    set connectors [list [linsert [dict get $signature open_span] 0 {[}]]
    foreach comma [dict get $signature comma_spans] {lappend connectors [linsert $comma 0 ,]}
    if {[dict exists $signature return_type_span]} {
        lassign [dict get $signature return_type_span] start end
        lappend marks [add c return_type_mark $start $end]
        lappend connectors [linsert [dict get $signature return_keyword_span] 0 return]
    }
    lappend connectors [linsert [dict get $signature close_span] 0 {]}]
    lassign [dict get $signature span] start end
    set node [add c signature $start $end $marks $connectors]
    set tick [need c ' EXPECTED_SIGNATURE_ATTRIBUTE]
    set attribute [attribute c $prefix $tick]
    lassign [lindex $c(rows) $attribute] type start end children connectors candidates
    # The attribute is the latest row. Insert the signature between prefix and designator.
    lset c(rows) $attribute 3 [linsert $children 1 $node]
    return $attribute
}

proc ::vhdl_index::bounded::qualification {state prefix tick} {
    upvar 1 $state c
    set value [grouped_primary c]
    return [add c qualified [lindex $c(rows) $prefix 1] [lindex $c(rows) $value 2] \
        [list $prefix $value] [list $tick]]
}

# Parse a parenthesized suffix once. Expressions common to all candidates
# are shared. A formal, OPEN, or an overt range changes the candidate set.
proc ::vhdl_index::bounded::name_group {state prefix mode} {
    upvar 1 $state c
    enter c
    set start [lindex $c(rows) $prefix 1]
    set open [token c]
    set arguments {}
    set connectors [list $open]
    set named 0
    set callOnly 0
    set prefixType [lindex $c(rows) $prefix 0]
    set canIndex [expr {$prefixType ni {operator selected_operator character selected_character}}]
    while {1} {
        set arrow {}
        set formal {}
        set value [actual c]
        set type [lindex $c(rows) $value 0]
        if {[kind c] eq "=>"} {
            if {![formal_shape c $value]} {stop c malformed INVALID_FORMAL}
            set formal $value
            set arrow [token c]
            set value [actual c]
        } elseif {$arguments eq {} && ([kind c] in {range to downto} || $type in {range_attribute parameterized_range_attribute})} {
            if {$type eq "open"} {stop c malformed EXPECTED_RANGE_BOUND}
            set range [discrete c $value]
            set close [close_group c )]
            if {!$canIndex} {stop c malformed INVALID_SLICE_PREFIX [lrange $open 1 2]}
            if {$prefixType eq "range_attribute"} {stop c malformed EXPECTED_ATTRIBUTE_PARAMETER}
            return [add c slice $start [lindex $close 2] [list $prefix $range] [list $open $close] {slice}]
        }
        if {[::vhdl_index::grammar::association_order named [expr {$arrow ne {}}]]} {
            stop c malformed POSITIONAL_AFTER_NAMED
        }
        if {$arrow ne {} || $type eq "open"} {set callOnly 1}
        if {$arrow eq {}} {
            lappend arguments $value
        } else {
            lappend arguments [add c actual_association [lindex $c(rows) $formal 1] \
                [lindex $c(rows) $value 2] [list $formal $value] [list $arrow]]
        }
        if {[kind c] ne ","} {break}
        lappend connectors [token c]
    }
    set close [close_group c )]
    lappend connectors $close
    set one [expr {[llength $arguments] == 1 && !$callOnly}]
    if {$prefixType eq "range_attribute"} {
        if {!$one} {stop c malformed EXPECTED_ATTRIBUTE_PARAMETER}
        return [add c parameterized_range_attribute $start [lindex $close 2] \
            [linsert $arguments 0 $prefix] $connectors {attribute_parameter}]
    }

    set candidates {}
    if {!$callOnly && $canIndex} {lappend candidates indexed}
    if {$one && $canIndex && [is_type_mark c [lindex $arguments 0]]} {
        lappend candidates slice
    }
    set continues [expr {[kind c] in {. ( ' {[}}}]
    if {($mode eq "primary" || $continues) &&
        $prefixType in {identifier extended_identifier selected operator selected_operator attribute}} {
        lappend candidates function_call
    }
    if {$mode eq "primary" && $one && !$continues && [is_type_mark c $prefix] &&
        [conversion_operand c [lindex $arguments 0]]} {
        lappend candidates type_conversion
    }
    if {$one && $prefixType eq "attribute"} {lappend candidates attribute_parameter}
    if {$candidates eq {}} {stop c malformed NO_NAME_INTERPRETATION}
    return [add c name_suffix $start [lindex $close 2] [linsert $arguments 0 $prefix] $connectors $candidates]
}

proc ::vhdl_index::bounded::actual {state} {
    upvar 1 $state c
    if {[kind c] eq "open"} {return [leaf c open]}
    if {[kind c] eq "inertial"} {stop c malformed INERTIAL_PARAMETER}
    return [expression c]
}

proc ::vhdl_index::bounded::formal_shape {state value} {
    upvar 1 $state c
    set type [lindex $c(rows) $value 0]
    if {$type eq "name_suffix"} {
        lassign [lindex $c(rows) $value] type start end children connectors candidates
        if {"indexed" in $candidates || "slice" in $candidates || "attribute_parameter" in $candidates} {
            return 1
        }
        if {"function_call" in $candidates && [llength $children] == 2} {
            set argument [lindex $children 1]
            return [expr {[lindex $c(rows) $argument 0] in {identifier extended_identifier selected}}]
        }
        return 0
    }
    return [expr {$type in {identifier extended_identifier selected dereference slice external attribute subtype_attribute}}]
}

proc ::vhdl_index::bounded::conversion_operand {state value} {
    upvar 1 $state c
    while {[lindex $c(rows) $value 0] eq "group"} {
        set value [lindex $c(rows) $value 3 0]
    }
    return [expr {[lindex $c(rows) $value 0] ni {string null aggregate allocator}}]
}

proc ::vhdl_index::bounded::discrete {state left} {
    upvar 1 $state c
    set type [lindex $c(rows) $left 0]
    if {$type in {relation shift logical condition reduction}} {stop c malformed EXPECTED_SIMPLE_RANGE_BOUND}
    set start [lindex $c(rows) $left 1]
    if {[kind c] eq "range"} {
        if {![is_type_mark c $left]} {stop c malformed EXPECTED_DISCRETE_TYPE_MARK}
        set keyword [token c]
        set bound [simple c]
        set range [explicit_range c $bound]
        return [add c discrete_subtype $start [lindex $c(rows) $range 2] [list $left $range] [list $keyword]]
    }
    if {[kind c] in {to downto} || $type in {range_attribute parameterized_range_attribute}} {
        return [explicit_range c $left]
    }
    if {[is_type_mark c $left]} {
        return [add c discrete_subtype $start [lindex $c(rows) $left 2] [list $left]]
    }
    stop c malformed EXPECTED_DISCRETE_RANGE
}

proc ::vhdl_index::bounded::explicit_range {state left} {
    upvar 1 $state c
    set direction [kind c]
    if {$direction in {to downto}} {
        set operator [token c]
        set right [simple c]
        return [add c range [lindex $c(rows) $left 1] [lindex $c(rows) $right 2] \
            [list $left $right] [list $operator]]
    }
    if {[lindex $c(rows) $left 0] in {range_attribute parameterized_range_attribute}} {return $left}
    stop c malformed EXPECTED_RANGE_DIRECTION
}

proc ::vhdl_index::bounded::allocator {state} {
    upvar 1 $state c
    set keyword [token c]
    set mark [name c mark]
    if {[kind c] eq "'" && [kind c 1] eq "("} {
        set value [qualification c $mark [token c]]
    } else {
        set value [subtype c $mark allocator]
    }
    return [add c allocator [lindex $keyword 1] [lindex $c(rows) $value 2] [list $value] [list $keyword]]
}

proc ::vhdl_index::bounded::subtype {state mark context} {
    upvar 1 $state c
    set children [list $mark]
    set connectors {}
    if {[is_name [kind c] 0]} {
        if {$context eq "allocator"} {stop c malformed ALLOCATOR_RESOLUTION}
        set mark [name c mark]
        lappend children $mark
    }
    if {[kind c] eq "range"} {
        if {$context eq "allocator"} {stop c malformed ALLOCATOR_SCALAR_CONSTRAINT}
        lappend connectors [token c]
        lappend children [explicit_range c [simple c]]
    } else {
        set count 0
        while {[kind c] eq "("} {
            if {[incr count] > 1 && $c(edition) < 2008} {
                stop c malformed EDITION_ELEMENT_CONSTRAINT
            }
            lappend children [constraint c]
        }
    }
    return [add c subtype [lindex $c(rows) [lindex $children 0] 1] \
        [lindex $c(rows) [lindex $children end] 2] $children $connectors]
}

proc ::vhdl_index::bounded::constraint {state} {
    upvar 1 $state c
    enter c
    set open [token c]
    set connectors [list $open]
    set children {}
    if {$c(edition) == 2008 && [kind c] eq "open"} {
        lappend children [leaf c open]
    } else {
        while {1} {
            set value [simple c]
            if {[kind c] in {, )} && [lindex $c(rows) $value 0] in {slice name_suffix}} {
                if {$c(edition) < 2008} {stop c malformed EDITION_RECORD_CONSTRAINT}
                stop c unsupported RECORD_CONSTRAINT
            }
            lappend children [discrete c $value]
            if {[kind c] ne ","} {break}
            lappend connectors [token c]
        }
    }
    set close [close_group c )]
    return [add c constraint [lindex $open 1] [lindex $close 2] $children [linsert $connectors end $close]]
}

proc ::vhdl_index::bounded::external {state} {
    upvar 1 $state c
    enter c
    set open [token c]
    set category [kind c]
    if {$category ni {signal variable constant}} {stop c malformed EXPECTED_EXTERNAL_CLASS}
    set connectors [list $open [token c]]
    set path [external_path c]
    lappend connectors [need c : EXPECTED_EXTERNAL_COLON]
    if {[kind c] eq "("} {stop c unsupported EXTERNAL_ELEMENT_RESOLUTION}
    set indication [subtype c [name c mark] external]
    set close [close_group c >>]
    return [add c external [lindex $open 1] [lindex $close 2] [list $path $indication] \
        [linsert $connectors end $close]]
}

proc ::vhdl_index::bounded::external_path {state} {
    upvar 1 $state c
    set start [lindex [current_extent c] 0]
    set mode relative_path
    set connectors {}
    if {[kind c] in {@ .}} {
        if {[kind c] eq "@"} {set mode package_path} else {set mode absolute_path}
        lappend connectors [token c]
    } else {
        while {[kind c] eq "^"} {
            lappend connectors [token c] [need c . EXPECTED_EXTERNAL_DOT]
        }
    }
    set parts {}
    while {1} {
        set id [designator_node c unit]
        if {[kind c] eq "(" && $mode ne "package_path"} {
            enter c
            set open [token c]
            set value [expression c]
            set close [close_group c )]
            if {[kind c] ne "."} {stop c malformed EXPECTED_EXTERNAL_OBJECT}
            set id [add c generate_path [lindex $c(rows) $id 1] [lindex $close 2] \
                [list $id $value] [list $open $close]]
        }
        lappend parts $id
        if {[kind c] ne "."} {break}
        lappend connectors [token c]
    }
    if {$mode eq "package_path" && [llength $parts] < 3} {stop c malformed EXPECTED_PACKAGE_PATH}
    return [add c $mode $start [lindex $c(rows) $id 2] $parts $connectors]
}
