namespace eval ::vhdl_index::interface {
    namespace path ::vhdl_index::parser
    variable classes {constant signal variable file}
    variable modes {in out inout buffer linkage}
    variable genericKinds {type function procedure pure impure package}
}

proc ::vhdl_index::interface::kind {state {ahead 0}} {
    upvar 1 $state c
    if {$c(i) + $ahead >= $c(interfaceFence)} {return eof}
    return [peek c $ahead]
}

proc ::vhdl_index::interface::problem {state code {detail {}}} {
    upvar 1 $state c
    return [dict merge [dict create code $code severity error span [span c]] $detail]
}

proc ::vhdl_index::interface::reject {state code {detail {}}} {
    upvar 1 $state c
    return -code error -errorcode {VHDL_INDEX INTERFACE} [problem c $code $detail]
}

proc ::vhdl_index::interface::require {state label code} {
    upvar 1 $state c
    if {[kind c] ne $label} {reject c $code [list expected $label found [kind c]]}
    return [take c]
}

proc ::vhdl_index::interface::name_span {state {operator 0}} {
    upvar 1 $state c
    set next [kind c]
    if {$next ni {identifier extended_identifier} && !($operator && $next eq "string")} {
        reject c INTERFACE_EXPECTED_NAME
    }
    return [take c]
}

proc ::vhdl_index::interface::extent {state start} {
    upvar 1 $state c
    return [list $start [lindex [span c previous] 1]]
}

# The caller owns the surrounding interface list. Its semicolons never enter
# opaque payloads. Local groups (constraints, defaults and maps) own their
# internal delimiters and cannot consume beyond the proved site fence.
proc ::vhdl_index::interface::group {state {recover 0}} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set pairs {{(} {)} {[} {]} << >>}
    set stack [list [dict get $pairs [kind c]]]
    incr c(i)
    if {!$recover && [lindex $stack end] eq ")" && [kind c] eq ")"} {
        reject c INTERFACE_EMPTY_GROUP
    }
    while {[llength $stack]} {
        set next [kind c]
        if {$next in {eof end begin}} {reject c INTERFACE_UNCLOSED_GROUP}
        if {[dict exists $pairs $next]} {
            if {[llength $stack] >= $c(delimiters)} {reject c INTERFACE_DELIMITER_LIMIT}
            lappend stack [dict get $pairs $next]
        } elseif {$next in {) ] >>}} {
            if {$next ne [lindex $stack end]} {reject c INTERFACE_MISMATCHED_DELIMITER}
            set stack [lreplace $stack end end]
        } elseif {!$recover && $next in {invalid unsupported {;}}} {
            reject c INTERFACE_INVALID_GROUP_TOKEN [list found $next]
        }
        incr c(i)
    }
    return [extent c $start]
}

# A colon cannot belong to these depth-zero payloads. A grouped next
# declarator is recognized at its first name, before consuming its comma.
proc ::vhdl_index::interface::item_prefix {state} {
    variable classes
    variable genericKinds
    upvar 1 $state c
    set first [kind c]
    return [expr {$first in $classes || $first in $genericKinds ||
        ($first in {identifier extended_identifier} && [kind c 1] in {: ,})}]
}

proc ::vhdl_index::interface::payload {state stops} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set first $c(i)
    while {1} {
        set next [kind c]
        if {$next in $stops || [item_prefix c]} {break}
        if {$next in {eof end begin}} {reject c INTERFACE_TRUNCATED_PAYLOAD}
        if {$next in {invalid unsupported ] >> : :=}} {
            reject c INTERFACE_INVALID_PAYLOAD_TOKEN [list found $next]
        }
        if {$next in {( [ <<}} {
            group c
        } else {
            incr c(i)
        }
    }
    if {$c(i) == $first} {reject c INTERFACE_EMPTY_PAYLOAD}
    set last [peek c -1]
    if {$last in {+ - * / ** & = /= => , to downto and or xor not} ||
        ($last eq "range" && ($c(i) - $first < 3 || [peek c -2] ne "'"))} {
        reject c INTERFACE_INCOMPLETE_PAYLOAD
    }
    return [extent c $start]
}

proc ::vhdl_index::interface::selected_name {state {operator 0} {attributes 0}} {
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

proc ::vhdl_index::interface::subtype_indication {state} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    if {[kind c] eq "("} {
        if {$c(edition) < 2008} {reject c EDITION_COMPOSITE_RESOLUTION}
        group c
        selected_name c 0 1
    } else {
        selected_name c 0 1
        # A resolution function may precede a second, selected type mark.
        if {[kind c] in {identifier extended_identifier} && ![item_prefix c]} {
            selected_name c 0 1
        }
    }
    if {[kind c] eq "range"} {
        incr c(i)
        payload c {bus := {;} )}
    } else {
        set count 0
        while {[kind c] eq "("} {
            if {$c(edition) < 2008 && [incr count] > 1} {reject c EDITION_ELEMENT_CONSTRAINT}
            group c
        }
    }
    return [extent c $start]
}

proc ::vhdl_index::interface::object {state context} {
    variable classes
    variable modes
    upvar 1 $state c
    set start [lindex [span c] 0]
    set explicitClass {}
    set classSpan {}
    if {[kind c] in $classes} {
        set explicitClass [kind c]
        set classSpan [take c]
    }
    set names [list [name_span c]]
    set commas {}
    while {[kind c] eq ","} {
        lappend commas [take c]
        lappend names [name_span c]
    }
    set colon [require c : INTERFACE_EXPECTED_COLON]
    set explicitMode {}
    set modeSpan {}
    if {[kind c] in $modes} {
        set explicitMode [kind c]
        set modeSpan [take c]
    }
    set mode $explicitMode
    if {$mode eq {}} {set mode in}
    if {$context eq "generic"} {
        set class constant
    } elseif {$context eq "port"} {
        set class signal
    } elseif {$mode in {out inout}} {
        set class variable
    } else {
        set class constant
    }
    if {$explicitClass ne {}} {set class $explicitClass}
    if {$class eq "file"} {set mode {}}
    set subtype [subtype_indication c]
    set bus {}
    if {[kind c] eq "bus"} {set bus [take c]}
    set marker {}
    set default {}
    if {[kind c] eq ":="} {
        set marker [take c]
        set default [payload c {{;} ) generic port}]
    }
    set diagnostics {}
    if {($context eq "generic" && $class ne "constant") || ($context eq "port" && $class ne "signal")} {
        lappend diagnostics [dict create code INTERFACE_INVALID_CLASS severity error span $classSpan]
    }
    if {($class eq "constant" && $mode ne "in") || ($class eq "file" && $explicitMode ne {}) ||
        ($context eq "parameter" && $mode in {linkage buffer})} {
        lappend diagnostics [dict create code INTERFACE_INVALID_MODE severity error span $modeSpan]
    }
    if {$bus ne {} && $class ne "signal"} {
        lappend diagnostics [dict create code INTERFACE_INVALID_BUS severity error span $bus]
    }
    if {$marker ne {} && ($class eq "file" || $mode eq "linkage" ||
        ($context eq "parameter" && ($class eq "signal" || ($class eq "variable" && $mode ne "in"))))} {
        lappend diagnostics [dict create code INTERFACE_INVALID_DEFAULT severity error span $marker]
    }
    set status [expr {$diagnostics eq {} ? "parsed" : "malformed"}]
    return [dict create category object span [extent c $start] names $names comma_spans $commas \
        colon_span $colon explicit_class $explicitClass class_span $classSpan effective_class $class \
        explicit_mode $explicitMode mode_span $modeSpan effective_mode $mode subtype_span $subtype \
        bus_span $bus default_marker_span $marker default_span $default status $status diagnostics $diagnostics]
}

proc ::vhdl_index::interface::generic_item {state context} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set form [kind c]
    set keyword [take c]
    set status parsed
    set diagnostics {}
    set kind $form
    if {$form in {function procedure pure impure}} {set kind subprogram}
    set item [dict create category $kind keyword_span $keyword]
    if {$kind eq "type"} {
        dict set item names [list [name_span c]]
        if {[kind c] eq "is"} {
            take c
            dict set item payload_span [payload c {{;} )}]
            set status recognized-but-unsupported
            lappend diagnostics [dict create code UNSUPPORTED_INTERFACE_TYPE_FORM severity error span $keyword]
        }
    } elseif {$kind eq "package"} {
        dict set item names [list [name_span c]]
        require c is INTERFACE_PACKAGE_EXPECTED_IS
        require c new INTERFACE_PACKAGE_EXPECTED_NEW
        dict set item package_target_span [selected_name c]
        set mapStart [lindex [require c generic INTERFACE_PACKAGE_EXPECTED_GENERIC] 0]
        require c map INTERFACE_PACKAGE_EXPECTED_MAP
        if {[kind c] ne "("} {reject c INTERFACE_EXPECTED_OPEN}
        set first [kind c 1]
        if {$first eq ")"} {reject c INTERFACE_EMPTY_MAP}
        set mapKind associations
        if {$first in {<> default}} {
            if {[kind c 2] ne ")"} {reject c INTERFACE_INVALID_MAP_FORM}
            set mapKind $first
        }
        dict set item map_group_span [group c]
        dict set item map_span [extent c $mapStart]
        dict set item map_kind $mapKind
    } else {
        set purity {}
        set puritySpan {}
        if {$form in {pure impure}} {
            set purity $form
            set puritySpan $keyword
            set form [kind c]
            require c function INTERFACE_EXPECTED_FUNCTION
        }
        dict set item subprogram_kind $form
        dict set item explicit_purity $purity
        dict set item purity_span $puritySpan
        if {$form eq "function"} {
            dict set item effective_purity [expr {$purity eq {} ? "pure" : $purity}]
        }
        dict set item names [list [name_span c [expr {$form eq "function"}]]]
        set parameterKeyword {}
        if {[kind c] eq "parameter"} {set parameterKeyword [take c]}
        if {[kind c] eq "(" || $parameterKeyword ne {}} {
            dict set item parameter_keyword_span $parameterKeyword
            set params [list_body c parameter]
            dict set item parameters $params
            set status [dict get $params status]
            lappend diagnostics {*}[dict get $params diagnostics]
        }
        if {$form eq "function"} {
            dict set item return_keyword_span [require c return INTERFACE_EXPECTED_RETURN]
            dict set item return_type_span [selected_name c 0 1]
        }
        if {[kind c] eq "is"} {
            dict set item default_marker_span [take c]
            if {[kind c] eq "<>"} {
                dict set item default_designator_span [take c]
            } else {
                dict set item default_designator_span [selected_name c [expr {$form eq "function"}]]
            }
        }
    }
    if {$context ne "generic"} {
        set status malformed
        lappend diagnostics [dict create code INTERFACE_CATEGORY_OUT_OF_CONTEXT severity error span $keyword]
    } elseif {$c(edition) < 2008} {
        if {$status eq "parsed"} {set status recognized-but-unsupported}
        lappend diagnostics [dict create code EDITION_INTERFACE_CATEGORY severity error span $keyword]
    }
    dict set item span [extent c $start]
    dict set item status $status
    dict set item diagnostics $diagnostics
    return $item
}

# Resynchronize with a fresh local delimiter stack. Only a semicolon at list
# depth or the list's closing parenthesis may end a discarded item.
proc ::vhdl_index::interface::recover_item {state start} {
    upvar 1 $state c
    set c(i) $start
    while {1} {
        set next [kind c]
        if {$next in {eof {;} )}} {return}
        if {$next in {( [ <<}} {
            group c 1
        } else {
            incr c(i)
        }
    }
}

proc ::vhdl_index::interface::combine {status next} {
    set severity {parsed recognized-but-unsupported malformed unrecognized}
    if {[lsearch -exact $severity $next] > [lsearch -exact $severity $status]} {return $next}
    return $status
}

proc ::vhdl_index::interface::list_body {state context} {
    variable genericKinds
    upvar 1 $state c
    set open [require c ( INTERFACE_EXPECTED_OPEN]
    set separators {}
    set items {}
    set diagnostics {}
    set status parsed
    if {[kind c] eq ")"} {
        lappend diagnostics [problem c INTERFACE_EMPTY_LIST]
        set status malformed
    }
    while {[kind c] ne ")"} {
        set first $c(i)
        set start [lindex [span c] 0]
        set caught [catch {
            if {$context ne "parameter" && [kind c] in $genericKinds} {
                set item [generic_item c $context]
            } else {
                set item [object c $context]
            }
            if {[kind c] ni {{;} )} && ![item_prefix c]} {
                reject c INTERFACE_UNEXPECTED_ITEM_TAIL [list found [kind c]]
            }
        } diagnostic options]
        if {$caught} {
            if {[dict get $options -errorcode] ne {VHDL_INDEX INTERFACE}} {
                return -options $options $diagnostic
            }
            recover_item c $first
            if {$c(i) > $first} {set itemSpan [extent c $start]} else {set itemSpan [list $start $start]}
            set item [dict create category unknown names {} status malformed span $itemSpan \
                diagnostics [list $diagnostic]]
        }
        set next [kind c]
        if {$next eq "eof"} {reject c INTERFACE_UNCLOSED_LIST}
        set status [combine $status [dict get $item status]]
        lappend diagnostics {*}[dict get $item diagnostics]
        lappend items $item
        if {$next eq ";"} {
            lappend separators [take c]
            if {[kind c] eq ")"} {
                lappend diagnostics [problem c INTERFACE_TRAILING_SEPARATOR]
                set status malformed
            }
        } elseif {$next ne ")"} {
            if {$c(i) <= $first} {reject c INTERFACE_NO_PROGRESS}
            lappend diagnostics [problem c INTERFACE_MISSING_ITEM_SEPARATOR]
            set status malformed
        }
    }
    set close [take c]
    return [dict create open_span $open close_span $close separator_spans $separators \
        items $items status $status diagnostics $diagnostics]
}

proc ::vhdl_index::interface::clause {state form} {
    upvar 1 $state c
    set keyword [take c]
    set result [list_body c $form]
    set semicolon {}
    if {[kind c] eq ";"} {
        set semicolon [take c]
    } else {
        dict lappend result diagnostics [problem c INTERFACE_MISSING_CLAUSE_SEMICOLON]
        dict set result status malformed
    }
    return [dict merge $result [dict create kind $form keyword_span $keyword semicolon_span $semicolon \
        span [extent c [lindex $keyword 0]]]]
}

# Look for the concrete legacy split-keyword failure without generalizing
# arbitrary misspelled entity declaration starters into interface clauses.
proc ::vhdl_index::interface::split_keyword {state} {
    upvar 1 $state c
    if {[peek c] ne "identifier" || [peek c 1] ne "identifier" || [peek c 2] ne "("} {return {}}
    set first [span c]
    incr c(i)
    set second [span c]
    incr c(i) -1
    set candidate [string tolower "[::vhdl_index::slice $c(snapshot) $first][::vhdl_index::slice $c(snapshot) $second]"]
    if {$candidate in {generic port}} {return $candidate}
    return {}
}

proc ::vhdl_index::interface::index_entity {state owner sites} {
    upvar 1 $state c
    set resume $c(i)
    set clauses {}
    set diagnostics {}
    set status parsed
    set seen {}
    foreach site $sites {
        lassign $site c(i) c(interfaceFence) placement split
        while {$c(i) < $c(interfaceFence)} {
            set first $c(i)
            set keyword [span c]
            set form [kind c]
            if {$split ne {}} {
                set form $split
                set split {}
                set diagnostic [problem c SPLIT_INTERFACE_KEYWORD]
                incr c(i)
                dict set diagnostic span [list [lindex $keyword 0] [lindex [span c] 1]]
                set failed 1
            } elseif {$form ni {generic port}} {
                set diagnostic [problem c UNRECOGNIZED_INTERFACE_FRAGMENT]
                set failed 1
            } else {
                set failed [catch {clause c $form} record options]
                if {$failed} {
                    if {[dict get $options -errorcode] ne {VHDL_INDEX INTERFACE}} {
                        return -options $options $record
                    }
                    set diagnostic $record
                }
            }
            if {$failed} {
                set c(i) $c(interfaceFence)
                set record [dict create kind $form keyword_span $keyword status malformed \
                    span [extent c [lindex $keyword 0]] items {} diagnostics [list $diagnostic]]
            }
            if {!$placement || $form in $seen || ($form eq "generic" && "port" in $seen)} {
                dict lappend record diagnostics [dict create code INTERFACE_INVALID_CLAUSE_ORDER \
                    severity error span $keyword]
                dict set record status malformed
            }
            lappend seen $form
            set record [account_lexical c $record]
            set status [combine $status [dict get $record status]]
            lappend diagnostics {*}[dict get $record diagnostics]
            lappend clauses $record
            if {$c(i) <= $first} {error "Interface site did not advance"}
        }
    }
    set c(i) $resume
    return [dict create source_id [dict get $c(snapshot) id] owner_name_span [dict get $owner name_span] \
        owner_span [dict get $owner span] clauses $clauses status $status diagnostics $diagnostics]
}

# Rare lexical diagnostics with otherwise recognizable tokens still invalidate
# their containing clause. Lexical causes keep their original span and code.
proc ::vhdl_index::interface::account_lexical {state record} {
    upvar 1 $state c
    lassign [dict get $record span] start end
    set at $c(interfaceLexicalAt)
    while {$at < [llength $c(interfaceLexical)]} {
        set diagnostic [lindex $c(interfaceLexical) $at]
        set where [lindex [dict get $diagnostic span] 0]
        if {$where >= $end} {break}
        incr at
        if {$where >= $start} {
            dict set diagnostic phase lexical
            set record [annotate_lexical $record $diagnostic $where]
        }
    }
    set c(interfaceLexicalAt) $at
    return $record
}

# Lexical errors in an object or a formal parameter are also attributable
# at item level. This runs only for overlapping lexical diagnostics.
proc ::vhdl_index::interface::annotate_lexical {record diagnostic where} {
    dict set record status malformed
    dict lappend record diagnostics $diagnostic
    set items {}
    foreach item [dict get $record items] {
        lassign [dict get $item span] start end
        if {$where >= $start && $where < $end} {
            dict set item status malformed
            dict lappend item diagnostics $diagnostic
            if {[dict exists $item parameters]} {
                set params [dict get $item parameters]
                set first [lindex [dict get $params open_span] 0]
                set last [lindex [dict get $params close_span] 1]
                if {$where >= $first && $where < $last} {
                    dict set item parameters [annotate_lexical $params $diagnostic $where]
                }
            }
        }
        lappend items $item
    }
    dict set record items $items
    return $record
}
