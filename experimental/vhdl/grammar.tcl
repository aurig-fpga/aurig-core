# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::grammar {
    namespace path ::vhdl_index::parser
}

proc ::vhdl_index::grammar::kind {state {ahead 0}} {
    upvar 1 $state c
    if {$c(i) + $ahead >= $c(grammarFence)} {return eof}
    return [peek c $ahead]
}

proc ::vhdl_index::grammar::problem {state code {detail {}}} {
    upvar 1 $state c
    if {![string match EDITION_* $code]} {set code ${c(grammarDomain)}_$code}
    return [diagnostic c $code $detail]
}

proc ::vhdl_index::grammar::reject {state code {detail {}}} {
    upvar 1 $state c
    return -code error -errorcode [list VHDL_INDEX $c(grammarDomain)] [problem c $code $detail]
}

proc ::vhdl_index::grammar::require {state label code} {
    upvar 1 $state c
    if {[kind c] ne $label} {reject c $code [list expected $label found [kind c]]}
    return [take c]
}

proc ::vhdl_index::grammar::name_span {state {operator 0}} {
    upvar 1 $state c
    set next [kind c]
    if {![is_name $next $operator]} {
        reject c EXPECTED_NAME
    }
    return [take c]
}

proc ::vhdl_index::grammar::extent {state start} {
    upvar 1 $state c
    return [list $start [lindex [span c previous] 1]]
}

# The caller owns the fence and policy. Scan uses the same delimiter stack
# as the outer structural walk and returns after the matching close.
proc ::vhdl_index::grammar::group {state {recover 0}} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    scan c {} [expr {$recover ? "recover" : "strict"}]
    return [extent c $start]
}

namespace eval ::vhdl_index::grammar {
    variable declarationFamilies {
        constant object signal object variable object shared object
        type type subtype type file opaque alias opaque attribute opaque
        function opaque procedure opaque pure opaque impure opaque
        component opaque package opaque group opaque disconnect opaque use opaque for opaque
    }
}

proc ::vhdl_index::grammar::declaration_family {keyword} {
    variable declarationFamilies
    if {[dict exists $declarationFamilies $keyword]} {
        return [dict get $declarationFamilies $keyword]
    }
    return {}
}

# The caller proves delimiter depth and selects a declarative context. Only a
# declaration-shaped prefix can end an object. Weak prefixes are evidence of
# uncertainty there. In an opaque header they may be grammatical (file OF,
# an attribute specification's entity class, or a binding indication).
proc ::vhdl_index::grammar::declaration_start {state context} {
    upvar 1 $state c
    set first [peek c]
    set previous [peek c -1]
    if {$previous eq "'" || ($first eq "variable" && $previous eq "shared") ||
        ($first in {function procedure} && $previous in {pure impure})} {
        return {}
    }

    set name [peek c 1]
    set connector [peek c 2]
    set named [is_name $name 0]
    switch -- $first {
        constant - signal - variable - shared - file - disconnect - for {
            set at 1
            if {$first eq "shared"} {
                if {$name ne "variable"} {return uncertain}
                incr at
                set name $connector
            }
            set named [expr {[is_name $name 0] || ($first in {for disconnect} && $name in {all others})}]
            if {$context ne "object" && $first in {constant signal variable shared} && $named} {
                # Preserve the conservative D observation inside opaque sites.
                return safe
            }
            while {$named && [peek c [incr at]] eq ","} {
                set named [is_name [peek c [incr at]] 0]
            }
            set safe [expr {$named && [peek c $at] eq ":"}]
        }
        type {set safe [expr {$named && $connector in {is {;}}}]}
        subtype {set safe [expr {$named && $connector eq "is"}]}
        alias {
            set safe [expr {([is_name $name 1] || $name eq "character") && $connector in {is :}}]
        }
        attribute {set safe [expr {$named && $connector in {: of}}]}
        group {set safe [expr {$named && $connector in {is :}}]}
        component {set safe [expr {$named && $connector in {is generic port end}}]}
        package {
            # A local package and a new design unit have the same prefix.
            # Leave that ambiguity to the structural unit-boundary guard.
            return {}
        }
        use {set safe [expr {$named && $connector eq "."}]}
        pure - impure - function - procedure {
            if {$first in {pure impure}} {
                set first $name
                set name $connector
                set connector [peek c 3]
            }
            set safe [expr {[is_name $name 1] &&
                (($first eq "function" && $connector in {( return generic is}) ||
                 ($first eq "procedure" && $connector in {( is generic {;}}))}]
        }
    }
    if {$safe} {return safe}
    return uncertain
}

# A colon cannot belong to these depth-zero payloads. A grouped next
# declarator is recognized at its first name, before consuming its comma.
proc ::vhdl_index::grammar::item_prefix {state} {
    upvar 1 $state c
    set first [kind c]
    return [expr {$first in $c(grammarPrefixes) ||
        ($c(grammarNamePrefix) && $first in {identifier extended_identifier} && [kind c 1] in {: ,})}]
}

proc ::vhdl_index::grammar::payload {state stops} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set first $c(i)
    while {1} {
        set next [kind c]
        if {$next in $stops || [item_prefix c]} {break}
        if {$next in {eof end begin}} {reject c TRUNCATED_PAYLOAD}
        if {$next in {invalid unsupported ] >> : :=}} {
            reject c INVALID_PAYLOAD_TOKEN [list found $next]
        }
        if {$next in {( [ <<}} {
            group c
        } else {
            incr c(i)
        }
    }
    if {$c(i) == $first} {reject c EMPTY_PAYLOAD}
    set last [peek c -1]
    if {$last in {+ - * / ** & = /= => , to downto and or xor not} ||
        ($last eq "range" && ($c(i) - $first < 3 || [peek c -2] ne "'"))} {
        reject c INCOMPLETE_PAYLOAD
    }
    return [extent c $start]
}

proc ::vhdl_index::grammar::selected_name {state {operator 0} {attributes 0}} {
    upvar 1 $state c
    set start [lindex [name_span c $operator] 0]
    while {1} {
        set next [kind c]
        if {$next eq "."} {
            incr c(i)
            name_span c $operator
        } elseif {$attributes && $next eq "'"} {
            incr c(i)
            if {$c(edition) == 2008 && [kind c] eq "subtype"} {
                incr c(i)
            } else {
                name_span c
            }
        } else {
            break
        }
    }
    return [extent c $start]
}

proc ::vhdl_index::grammar::subtype_indication {state rangeStops} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set resolution {}
    set resolutionKind {}
    if {[kind c] eq "("} {
        if {$c(edition) < 2008} {reject c EDITION_COMPOSITE_RESOLUTION}
        set resolution [group c]
        set resolutionKind composite
        set mark [selected_name c 0 1]
    } else {
        set mark [selected_name c 0 1]
        # A resolution function may precede a second, selected type mark.
        if {[kind c] in {identifier extended_identifier} && ![item_prefix c]} {
            set resolution $mark
            set resolutionKind scalar
            set mark [selected_name c 0 1]
        }
    }
    set constraint {}
    if {[kind c] in {range (}} {set constraintStart [lindex [span c] 0]}
    if {[kind c] eq "range"} {
        incr c(i)
        payload c $rangeStops
    } else {
        set count 0
        while {[kind c] eq "("} {
            if {$c(edition) < 2008 && [incr count] > 1} {reject c EDITION_ELEMENT_CONSTRAINT}
            group c
        }
    }
    if {[info exists constraintStart]} {set constraint [extent c $constraintStart]}
    return [list [extent c $start] $constraint $mark $resolution $resolutionKind]
}


# Exact suffix of the single-identifier, simple-type-mark production.
# Callers provide a fence and handle their own class, mode and separator rules.
proc ::vhdl_index::grammar::simple_declarator {state} {
    upvar 1 $state c
    return [expr {[is_name [kind c 1] 0] && [kind c 2] eq ":" &&
        [is_name [kind c 3] 0] && [kind c 4] eq ";"}]
}

proc ::vhdl_index::grammar::identifier_list {state} {
    upvar 1 $state c
    set names [list [name_span c]]
    set commas {}
    while {[kind c] eq ","} {
        lappend commas [take c]
        lappend names [name_span c]
    }
    return [list $names $commas [require c : EXPECTED_COLON]]
}

# Each capability walks lexical provenance in source order with its own cursor.
proc ::vhdl_index::grammar::lexical_diagnostics {state region cursor} {
    upvar 1 $state c
    lassign $region start end
    set found {}
    while {$c($cursor) < [llength $c(declarationLexical)]} {
        set issue [lindex $c(declarationLexical) $c($cursor)]
        set where [lindex [dict get $issue span] 0]
        if {$where >= $end} {break}
        incr c($cursor)
        if {$where >= $start} {
            dict set issue phase lexical
            lappend found $issue
        }
    }
    return $found
}

proc ::vhdl_index::grammar::combine {status next} {
    set severity {parsed recognized-but-unsupported malformed unrecognized}
    if {[lsearch -exact $severity $next] > [lsearch -exact $severity $status]} {return $next}
    return $status
}
