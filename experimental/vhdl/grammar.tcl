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
    set extent [take c]
    if {$next eq "string"} {validate_operator c $extent}
    return $extent
}

# String tokens can use either lexical delimiter in editions that accept it.
# Validate the operator image while retaining the caller's exact source span.
proc ::vhdl_index::grammar::validate_operator {state extent} {
    upvar 1 $state c
    set image [::vhdl_index::slice $c(snapshot) $extent]
    set symbol [string tolower [string range $image 1 end-1]]
    set details [list span $extent designator_span $extent]
    if {$symbol ni {** abs not * / mod rem + - & sll srl sla sra rol ror
        = /= < <= > >= and or nand nor xor xnor ?= ?/= ?< ?<= ?> ?>= ??}} {
        reject c INVALID_OPERATOR $details
    }
    if {$c(edition) < 2008 && [string index $symbol 0] eq "?"} {
        reject c EDITION_OPERATOR $details
    }
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
        type type subtype type file file_object alias alias attribute attribute
        function subprogram procedure subprogram pure subprogram impure subprogram
        component component package opaque group group disconnect disconnect use local_use for configuration_specification
    }
}

proc ::vhdl_index::grammar::declaration_family {keyword} {
    variable declarationFamilies
    if {[dict exists $declarationFamilies $keyword]} {
        return [dict get $declarationFamilies $keyword]
    }
    return {}
}

# Inspect only the bounded header slots shared by a family. A missing
# identifier can leave the discriminator in the first slot.
proc ::vhdl_index::grammar::candidate_forms {state discriminators} {
    upvar 1 $state c
    set first [kind c]
    if {[dict exists $discriminators $first]} {
        return [list [dict get $discriminators $first]]
    }
    set next [kind c 1]
    if {$first ni {eof ( ) {[} {]} << >> {;} ,} && [dict exists $discriminators $next]} {
        return [list [dict get $discriminators $next]]
    }
    return [dict values $discriminators]
}

# The caller proves delimiter depth and selects a declarative context. Only a
# declaration-shaped prefix can end an object. Weak prefixes are evidence of
# uncertainty there. In an opaque header they may be grammatical (file OF,
# an attribute specification's entity class, or a binding indication).
proc ::vhdl_index::grammar::declaration_start {state context} {
    upvar 1 $state c
    set first [peek c]
    set previous [peek c -1]
    if {$context eq "configuration_specification" && $first eq "use" &&
        [peek c 1] in {entity configuration open vunit}} {
        return {}
    }
    if {$context eq "attribute_item" && $previous eq ":" && [peek c 1] eq "is"} {
        # At this position an attribute specification admits an entity class.
        return {}
    }
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
            if {$context ni {object indexed_item attribute_item configuration_specification} && $first in {constant signal variable shared} && $named} {
                # Preserve the conservative D observation inside opaque sites.
                return safe
            }
            if {$first eq "disconnect" && $named && $connector in {. ( ,}} {
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
                (($first eq "function" && $connector in {( return generic parameter is}) ||
                 ($first eq "procedure" && $connector in {( is generic parameter {;}}))}]
        }
    }
    if {$safe} {return safe}
    return uncertain
}

# A colon cannot belong to these depth-zero payloads. A grouped next
# declarator is recognized at its first name, before consuming its comma.
proc ::vhdl_index::grammar::item_prefix {state} {
    upvar 1 $state c
    if {$c(grammarNamePrefix) eq "record"} {return [record_field_prefix c]}
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
        } elseif {$next eq "'" && ($attributes eq "1" ||
            ($attributes eq "subtype" && [kind c 1] eq "subtype"))} {
            incr c(i)
            if {[kind c] eq "subtype" && $c(edition) == 2008} {
                incr c(i)
            } elseif {[kind c] eq "subtype" && $c(grammarDomain) eq "TYPE"} {
                reject c EDITION_SUBTYPE_ATTRIBUTE
            } else {
                name_span c
            }
        } else {
            break
        }
    }
    return [extent c $start]
}

# A simple designator can also denote a character literal or an operator.
proc ::vhdl_index::grammar::designator {state} {
    upvar 1 $state c
    set form [kind c]
    if {$form eq "character"} {return [list [take c] $form]}
    set extent [name_span c 1]
    if {$form eq "string"} {set form operator}
    return [list $extent $form]
}

# Both clause callers use these selected-name slots. A root caller can
# retain an invalid operator and continue to the next comma or terminator.
proc ::vhdl_index::grammar::context_names {state clause {issuesVar {}}} {
    upvar 1 $state c
    if {$issuesVar ne {}} {upvar 1 $issuesVar issues}
    set names {}
    set commas {}
    while {1} {
        set first [name_span c]
        set components [list $first]
        if {$clause ne "library"} {
            require c . EXPECTED_DOT
            while {1} {
                set suffix [kind c]
                if {$clause eq "use" && $suffix in {all character string}} {
                    set selected [take c]
                    if {$suffix eq "string"} {
                        if {$issuesVar eq {}} {
                            validate_operator c $selected
                        } elseif {[catch {validate_operator c $selected} diagnostic options]} {
                            if {[dict get $options -errorcode] ne {VHDL_INDEX CONTEXT}} {
                                return -options $options $diagnostic
                            }
                            lappend issues $diagnostic
                        }
                    }
                    lappend components $selected
                    break
                }
                lappend components [name_span c]
                if {[kind c] ne "."} {break}
                take c
            }
        }
        set selection [list [lindex $first 0] [lindex $components end 1]]
        lappend names [dict create span $selection components $components]
        if {[kind c] ne ","} {break}
        lappend commas [take c]
    }
    return [list $names $commas]
}

proc ::vhdl_index::grammar::entity_class {state} {
    upvar 1 $state c
    set class [kind c]
    if {$class ni {entity architecture configuration procedure function package type subtype
        constant signal variable component label literal units group file property sequence}} {
        reject c EXPECTED_ENTITY_CLASS
    }
    return [list $class [take c]]
}

proc ::vhdl_index::grammar::signature {state} {
    upvar 1 $state c
    set open [require c {[} EXPECTED_SIGNATURE_OPEN]
    set marks {}
    set commas {}
    if {[kind c] ni {return {]}}} {
        lappend marks [selected_name c 0 1]
        while {[kind c] eq ","} {
            lappend commas [take c]
            lappend marks [selected_name c 0 1]
        }
    }
    set result [dict create open_span $open type_mark_spans $marks comma_spans $commas]
    if {[kind c] eq "return"} {
        dict set result return_keyword_span [take c]
        dict set result return_type_span [selected_name c 0 1]
    }
    dict set result close_span [require c {]} EXPECTED_SIGNATURE_CLOSE]
    dict set result span [extent c [lindex $open 0]]
    return $result
}

# These two attributes can constitute the whole range. A name prefix may
# contain selected components, indices, calls and other attributes.
proc ::vhdl_index::grammar::range_attribute {state stops} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    name_span c
    while {1} {
        switch -- [kind c] {
            . {
                incr c(i)
                name_span c
            }
            ( {group c}
            ' {
                incr c(i)
                set attribute [kind c]
                set attributeSpan [span c]
                if {$attribute eq "range" || ($attribute eq "identifier" &&
                    [string equal -nocase reverse_range [::vhdl_index::slice $c(snapshot) $attributeSpan]])} {
                    incr c(i)
                    if {[kind c] eq "("} {group c}
                    if {[kind c] in $stops} {return [extent c $start]}
                    reject c EXPECTED_RANGE_DIRECTION
                }
                if {$c(edition) == 2008 && $attribute eq "subtype"} {
                    incr c(i)
                } else {
                    name_span c
                }
            }
            default {reject c EXPECTED_RANGE_DIRECTION}
        }
    }
}

proc ::vhdl_index::grammar::range_payload {state stops} {
    upvar 1 $state c
    set first $c(i)
    set left [payload c [concat $stops {to downto}]]
    set direction [kind c]
    if {$direction in {to downto}} {
        set directionSpan [take c]
        set right [payload c [concat $stops {to downto}]]
        if {[kind c] in {to downto}} {reject c MULTIPLE_RANGE_DIRECTIONS}
        return [list $left $direction $directionSpan $right {}]
    }
    set c(i) $first
    if {![is_name [kind c] 0]} {reject c EXPECTED_RANGE_DIRECTION}
    return [list {} {} {} {} [range_attribute c $stops]]
}

# An array index can be a type mark, an explicit range, or a range
# attribute. Only ARRAY's own index list admits a boxed index subtype.
proc ::vhdl_index::grammar::discrete_range {state allowBox} {
    upvar 1 $state c
    set first $c(i)
    set start [lindex [span c] 0]
    set stops {, )}
    set boundStops {, ) <> of}
    set row {}
    if {[kind c] in {, ) of range eof open <>}} {reject c EXPECTED_INDEX}
    if {[is_name [kind c] 0]} {
        set mark [selected_name c 0 subtype]
        set next [kind c]
        if {$next eq "range" || $next in $stops} {
            dict set row kind subtype
            dict set row type_mark_span $mark
            if {$next eq "range"} {
                set keyword [take c]
                dict set row range_keyword_span $keyword
                if {[kind c] eq "<>"} {
                    if {!$allowBox} {reject c UNEXPECTED_INDEX_BOX}
                    dict set row kind index_subtype
                    dict set row box_span [take c]
                } else {
                    lassign [range_payload c $boundStops] left direction directionSpan right attribute
                    dict set row range_span [extent c [lindex $keyword 0]]
                }
            }
        } else {
            if {[is_name $next 0]} {reject c EXPECTED_DIMENSION_SEPARATOR}
            set c(i) $first
        }
    }
    if {$row eq {}} {
        lassign [range_payload c $boundStops] left direction directionSpan right attribute
        dict set row kind [expr {$attribute eq {} ? "range" : "range_attribute"}]
        dict set row range_span [extent c $start]
    }
    if {[info exists direction]} {
        dict set row direction $direction
        dict set row direction_span $directionSpan
        dict set row left_bound_span $left
        dict set row right_bound_span $right
        dict set row range_attribute_span $attribute
    }
    dict set row span [extent c $start]
    return $row
}

# Parse an element constraint in a composite declaration. A simple field
# name followed by groups can denote a record element constraint. A range
# may instead start with a call or indexed name, so prove the group suffix
# ends at this level before choosing that production.
proc ::vhdl_index::grammar::record_constraint_prefix {state} {
    upvar 1 $state c
    if {![is_name [kind c] 0] || [kind c 1] ne "("} {return 0}
    set first $c(i)
    incr c(i)
    while {[kind c] eq "("} {group c}
    set found [expr {[kind c] in {, )}}]
    set c(i) $first
    return $found
}

proc ::vhdl_index::grammar::element_constraint {state} {
    upvar 1 $state c
    require c ( EXPECTED_CONSTRAINT_OPEN
    if {[kind c] eq "open"} {
        if {$c(edition) < 2008} {reject c EDITION_OPEN_CONSTRAINT}
        take c
    } else {
        set form {}
        while {1} {
            set field [record_constraint_prefix c]
            if {$form ne {} && $field != $form} {reject c MIXED_ELEMENT_CONSTRAINT}
            set form $field
            if {$field} {
                if {$c(edition) < 2008} {reject c EDITION_RECORD_CONSTRAINT}
                name_span c
                while {[kind c] eq "("} {element_constraint c}
            } else {
                discrete_range c 0
            }
            if {[kind c] ne ","} {break}
            take c
        }
    }
    require c ) EXPECTED_CONSTRAINT_CLOSE
}

# VHDL-2008 element resolution is either one indication for array
# elements or a list of named record elements with their own indications.
# The structural fence already enforced the global delimiter depth limit.
proc ::vhdl_index::grammar::resolution_group {state} {
    upvar 1 $state c
    set start [lindex [require c ( EXPECTED_RESOLUTION_OPEN] 0]
    if {[kind c] eq "("} {
        resolution_group c
    } else {
        set first $c(i)
        selected_name c 1
        if {[kind c] ne ")"} {
            if {$c(i) != $first + 1 || ![is_name [peek c -1] 0]} {
                reject c EXPECTED_RESOLVED_ELEMENT_NAME
            }
            while {1} {
                if {[kind c] eq "("} {
                    resolution_group c
                } else {
                    selected_name c 1
                }
                if {[kind c] ne ","} {break}
                incr c(i)
                name_span c
            }
        }
    }
    require c ) EXPECTED_RESOLUTION_CLOSE
    return [extent c $start]
}

proc ::vhdl_index::grammar::subtype_indication {state rangeStops {structuredRange 0} {composite 0}} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set resolution {}
    set resolutionKind {}
    if {[kind c] eq "("} {
        if {$c(edition) < 2008} {reject c EDITION_COMPOSITE_RESOLUTION}
        if {$structuredRange} {
            set resolution [resolution_group c]
        } else {
            set resolution [group c]
        }
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
        if {$structuredRange} {
            range_payload c $rangeStops
        } else {
            payload c $rangeStops
        }
    } else {
        set count 0
        while {[kind c] eq "("} {
            if {$c(edition) < 2008 && [incr count] > 1} {reject c EDITION_ELEMENT_CONSTRAINT}
            if {$composite} {
                element_constraint c
            } else {
                group c
            }
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

# A record field start is proved by its entire identifier list and colon.
# A single following name is also legal as the type mark after a resolution name.
proc ::vhdl_index::grammar::record_field_prefix {state} {
    upvar 1 $state c
    set offset 0
    while {[is_name [kind c $offset] 0]} {
        set next [kind c [incr offset]]
        if {$next eq ":"} {return 1}
        if {$next ne ","} {break}
        incr offset
    }
    return 0
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
