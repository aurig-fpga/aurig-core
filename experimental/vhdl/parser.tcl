# Context clauses keep exact whole-clause, selected-name and component spans.
proc ::vhdl_index::parser::context_item {state} {
    upvar 1 $state c
    set kind [peek c]
    set start [lindex [take c] 0]
    set names {}
    while {1} {
        lassign [read_name c] spelling extent
        set components [list $extent]
        if {$kind ne "library"} {
            expect c .
            while {1} {
                set suffix [peek c]
                if {$kind eq "use" && $suffix in {all character string}} {
                    lappend components [take c]
                    break
                }
                lassign [read_name c] _ part
                lappend components $part
                if {![accept c .]} {break}
            }
        }
        set selection [list [lindex $extent 0] [lindex $components end 1]]
        lappend names [dict create span $selection components $components]
        if {![accept c ,]} {break}
    }
    expect c {;}
    return [dict create kind $kind span [list $start [lindex [span c previous] 1]] names $names]
}

proc ::vhdl_index::parser::is_context_item {state} {
    upvar 1 $state c
    set kind [peek c]
    return [expr {$kind in {library use} || ($kind eq "context" && [peek c 2] ne "is")}]
}

proc ::vhdl_index::parser::terminator {state kind name {allowName 1} {matching 0}} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    expect c end
    set explicit 0
    if {$kind eq "process"} {accept c postponed}
    if {$kind in {package_body protected_body}} {
        set keyword [lindex [split $kind _] 0]
        if {[accept c $keyword]} {
            set explicit 1
            expect c body
        }
    } else {
        set explicit [accept c $kind]
    }
    if {!$explicit && $kind ni {entity architecture package package_body configuration context function procedure alternative}} {
        fail c MISMATCHED_END_KIND [list expected $kind found [peek c]]
    }
    if {$kind eq "case" && [accept c ?] != $matching} {
        fail c MISMATCHED_CASE_MARKER
    }
    if {$allowName && [peek c] in {identifier extended_identifier string}} {
        if {$kind ni {function procedure} && [peek c] eq "string"} {
            fail c EXPECTED_NAME
        }
        lassign [read_name c 1] spelling extent key
        if {[lindex $name 2] ne $key || $name eq {}} {
            if {!$explicit} {
                fail c UNCERTAIN_END_NAME [list actual_span $extent expected [lindex $name 0] found $spelling]
            }
            lappend c(diagnostics) [dict create code MISMATCHED_END_NAME severity error span $extent \
                related_span [lindex $name 1] expected [lindex $name 0] found $spelling]
        }
    }
    expect c {;}
    return [list $start [lindex [span c previous] 1]]
}

proc ::vhdl_index::parser::header {state} {
    upvar 1 $state c
    set kind [peek c]
    if {$kind ni {entity architecture configuration package context}} {
        fail c UNRECOGNIZED_ROOT [list found $kind]
    }
    set start [lindex [take c] 0]
    if {$kind eq "package" && [accept c body]} {set kind package_body}
    set name [read_name c]
    set target {}
    if {$kind in {architecture configuration}} {
        expect c of
        set target [read_name c]
    }
    expect c is
    return [list $kind $name [list $start [lindex [span c previous] 1]] $target]
}

# Recognize the package instantiation name and the generic map envelope.
# The actual associations remain deliberately opaque.
proc ::vhdl_index::parser::instantiation {state} {
    upvar 1 $state c
    if {$c(edition) < 2008} {fail c EDITION_PACKAGE_INSTANTIATION}
    expect c new
    read_name c
    while {[accept c .]} {read_name c}
    if {[accept c generic]} {
        expect c map
        consume_group c
    }
    return [take_semicolon c]
}

proc ::vhdl_index::parser::take_semicolon {state} {
    upvar 1 $state c
    if {[peek c] ne ";"} {fail c EXPECTED_TOKEN [list expected {;} found [peek c]]}
    return [take c]
}

proc ::vhdl_index::parser::boundary {state stops {declarationContext {}}} {
    upvar 1 $state c
    set marker [scan c $stops {} $declarationContext]
    if {$marker eq "eof"} {fail c TRUNCATED_SCOPE}
    return $marker
}

proc ::vhdl_index::parser::opaque_item {state {declarationContext {}}} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set first $c(i)
    set marker [boundary c {{;} end begin} $declarationContext]
    if {$marker eq ";"} {
        incr c(i)
    } elseif {$marker eq "declaration"} {
        return
    } elseif {$c(i) == $first} {
        fail c UNEXPECTED_BOUNDARY [list found $marker]
    } else {
        lappend c(diagnostics) [dict create code MISSING_SEMICOLON severity error \
            span [list $start [lindex [span c] 0]]]
    }
}

proc ::vhdl_index::parser::descend {state depth} {
    upvar 1 $state c
    if {$depth >= $c(scopes)} {fail c SCOPE_LIMIT}
    return [expr {$depth + 1}]
}

# A candidate buried in an opaque item is evidence of an uncertain fence.
# It is never promoted to a sibling without a proved boundary.
proc ::vhdl_index::parser::opaque_object_boundary {state observing} {
    upvar 1 $state c
    if {!$observing || $c(opaqueBoundary) eq {}} {return 0}
    lappend c(objectDiagnostics) [::vhdl_index::object::at OBJECT_OPAQUE_BOUNDARY $c(opaqueBoundary)]
    return 1
}

proc ::vhdl_index::parser::declaration {state depth {owner {}}} {
    upvar 1 $state c
    set first [peek c]
    set observe [expr {$owner ne {}}]
    set headerContext [expr {$observe ? "opaque_tail" : ""}]
    set itemContext [expr {$observe ? "opaque_item" : ""}]
    switch -- $first {
        impure - pure - function - procedure {
            if {$owner ne {}} {set opening [lindex [span c] 0]}
            if {$first in {impure pure}} {incr c(i)}
            set kind [peek c]
            if {$kind ni {function procedure}} {fail c EXPECTED_SUBPROGRAM}
            incr c(i)
            set name [read_name c 1]
            set marker [boundary c {is {;} end begin} $headerContext]
            set obscured [opaque_object_boundary c $observe]
            if {$marker eq "is"} {
                incr c(i)
                if {[peek c] ne "new"} {
                    set child {}
                    if {$observe && !$obscured} {set child [list $opening $owner]}
                    scope c $kind $name [descend c $depth] require $child
                    if {$obscured} {return uncertain_opaque_item}
                    return {}
                }
                if {$c(edition) < 2008} {fail c EDITION_SUBPROGRAM_INSTANTIATION}
                opaque_item c
            } elseif {$marker eq ";"} {
                incr c(i)
            } else {
                fail c INCOMPLETE_SUBPROGRAM_SPEC
            }
            if {$obscured} {return uncertain_opaque_item}
        }
        package {
            if {$c(edition) < 2008} {fail c EDITION_NESTED_PACKAGE}
            lassign [header c] kind name
            if {$kind eq "package" && [peek c] eq "new"} {
                instantiation c
            } else {
                scope c $kind $name [descend c $depth] forbid
            }
        }
        component {
            incr c(i)
            set name [read_name c]
            accept c is
            scope c component $name [descend c $depth] forbid
        }
        type {
            set firstType $c(i)
            incr c(i)
            set name {}
            if {!$observe || [is_name [peek c] 0]} {set name [read_name c]}
            if {[accept c is]} {
                set type [peek c]
                if {$type in {record protected}} {
                    incr c(i)
                    if {$type eq "protected" && [accept c body]} {set type protected_body}
                    scope c $type $name [descend c $depth] forbid
                    return $type
                }
                set marker $type
                set obscured 0
                if {$marker ne "units"} {
                    set marker [boundary c {units {;} end begin} $headerContext]
                    set obscured [opaque_object_boundary c $observe]
                }
                if {$marker eq "units"} {
                    expect c units
                    scope c units $name [descend c $depth] forbid
                    if {$obscured} {return uncertain_opaque_item}
                    return units
                }
                if {$observe && $marker ne ";"} {
                    if {$obscured} {return uncertain_opaque_item}
                    return type
                }
                opaque_item c
                if {$obscured} {return uncertain_opaque_item}
            } elseif {$observe} {
                # Include the introducer when fencing a malformed header or
                # an incomplete declaration with a missing terminator.
                set c(i) $firstType
                set marker [boundary c {{;} end begin} $itemContext]
                if {$marker eq ";"} {incr c(i)}
                if {[opaque_object_boundary c $observe]} {return uncertain_opaque_item}
            } else {
                opaque_item c
            }
        }
        subtype {
            if {$observe} {
                # END and BEGIN prove the owning fence even without a
                # declaration semicolon. The type production reports it.
                set marker [boundary c {{;} end begin} $itemContext]
                if {$marker eq ";"} {incr c(i)}
                if {[opaque_object_boundary c $observe]} {return uncertain_opaque_item}
            } else {
                opaque_item c
            }
        }
        for {
            opaque_item c
            if {$c(edition) >= 2008 && [peek c] eq "end" && [peek c 1] eq "for"} {
                terminator c for {} 0
            }
        }
        entity - architecture - context - configuration {
            fail c UNSAFE_UNIT_BOUNDARY [list found $first]
        }
        default {
            opaque_item c $itemContext
            if {[opaque_object_boundary c $observe]} {return uncertain_opaque_item}
        }
    }
    return $first
}

proc ::vhdl_index::parser::configuration_block {state depth} {
    upvar 1 $state c
    set child [descend c $depth]
    expect c for
    set start $c(i)
    set marker [boundary c {for end use {;}}]
    if {$start == $c(i)} {fail c INCOMPLETE_CONFIGURATION_HEADER}
    if {$marker eq ";"} {incr c(i)}
    configuration_part c $child
    terminator c for {} 0
}

# Configuration for-headers end before the first child, use binding or end.
proc ::vhdl_index::parser::configuration_part {state depth} {
    upvar 1 $state c
    while {[peek c] ne "end"} {
        set next [peek c]
        if {$next eq "for"} {
            configuration_block c $depth
        } elseif {$next in {use attribute group}} {
            opaque_item c
        } else {
            fail c EXPECTED_CONFIGURATION_ITEM [list found $next]
        }
    }
}

proc ::vhdl_index::parser::generate_body {state label depth} {
    upvar 1 $state c
    set phase flexible
    set sawBegin 0
    while {1} {
        switch -- [peek c] {
            end {
                if {$phase eq "declare"} {fail c MISSING_BEGIN}
                if {[peek c 1] eq "generate"} {return}
                if {$c(edition) < 2008} {fail c EDITION_GENERATE_BODY_END}
                terminator c alternative $label
                return
            }
            elsif - else - when {
                if {$phase eq "declare"} {fail c MISSING_BEGIN}
                return
            }
            begin {
                if {$c(edition) < 2008} {fail c EDITION_GENERATE_BEGIN}
                if {$sawBegin} {fail c DUPLICATE_BEGIN}
                incr c(i)
                set sawBegin 1
                set phase concurrent
            }
            eof {fail c TRUNCATED_GENERATE}
            default {
                set first [peek c]
                if {$phase eq "flexible" && $first in {alias attribute component constant disconnect file
                    function group impure package procedure pure shared signal subtype type use variable}} {
                    if {$c(edition) < 2008} {fail c EDITION_GENERATE_DECLARATION}
                    declaration c $depth
                    set phase declare
                } elseif {$phase eq "declare"} {
                    declaration c $depth
                } else {
                    statement c $depth concurrent
                    set phase concurrent
                }
            }
        }
    }
}

proc ::vhdl_index::parser::generate {state depth name form alternative} {
    upvar 1 $state c
    if {$name eq {}} {fail c MISSING_GENERATE_LABEL}
    set child [descend c $depth]
    if {$form eq "case"} {
        if {$c(edition) < 2008} {fail c EDITION_CASE_GENERATE}
        expect c when
        while {1} {
            set alternative [optional_label c]
            branch_header c =>
            generate_body c $alternative $child
            if {![accept c when]} {break}
        }
    } else {
        set sawElse 0
        while {1} {
            generate_body c $alternative $child
            set marker [peek c]
            if {$marker ni {elsif else}} {break}
            if {$form ne "if" || $c(edition) < 2008 || $sawElse} {fail c UNEXPECTED_GENERATE_ALTERNATIVE}
            incr c(i)
            set alternative [optional_label c]
            if {$marker eq "else"} {
                expect c generate
                set sawElse 1
            } else {
                branch_header c generate
            }
        }
    }
    terminator c generate $name
}

proc ::vhdl_index::parser::optional_label {state} {
    upvar 1 $state c
    if {[peek c] in {identifier extended_identifier} && [peek c 1] eq ":"} {
        set name [read_name c]
        incr c(i)
        return $name
    }
    return {}
}

proc ::vhdl_index::parser::branch_header {state marker} {
    upvar 1 $state c
    set start $c(i)
    if {[boundary c [list $marker {;} end begin]] ne $marker || $start == $c(i)} {
        fail c INCOMPLETE_BRANCH_HEADER [list expected $marker]
    }
    incr c(i)
}

proc ::vhdl_index::parser::statement {state depth phase {owner {}}} {
    upvar 1 $state c
    if {$owner ne {}} {set opening [lindex [span c] 0]}
    set label [optional_label c]
    set first [peek c]
    if {$first eq "postponed" && [peek c 1] eq "process"} {
        incr c(i)
        set first process
    }
    switch -- $first {
        process - block {
            if {$phase ne "concurrent"} {fail c UNEXPECTED_CONCURRENT_SCOPE}
            incr c(i)
            # Headers can have a delimiter group and an optional IS. The
            # declaration scan handles the following item independently.
            if {[peek c] eq "("} {consume_group c}
            accept c is
            set child {}
            if {$owner ne {} && $first eq "process"} {set child [list $opening $owner]}
            scope c $first $label [descend c $depth] require $child
            if {$first eq "block"} {return block}
        }
        if - case - for - while - loop {
            incr c(i)
            set alternative {}
            if {$phase eq "concurrent" && $first eq "if" && $c(edition) >= 2008} {
                set alternative [optional_label c]
            }
            set matching 0
            if {$first eq "case" && $phase eq "sequential"} {set matching [accept c ?]}
            if {$first eq "loop"} {
                set marker loop
            } else {
                set headerStart $c(i)
                set marker [boundary c {generate then loop is {;} end begin}]
                if {$headerStart == $c(i)} {fail c INCOMPLETE_STATEMENT_HEADER}
                incr c(i)
            }
            if {$marker eq "generate" && $phase eq "concurrent" && $first in {if case for}} {
                generate c $depth $label $first $alternative
                return generate
            } elseif {$phase eq "sequential" &&
                [dict exists {if then case is for loop while loop loop loop} $first] &&
                [dict get {if then case is for loop while loop loop loop} $first] eq $marker} {
                set kind $first
                if {$marker eq "loop"} {set kind loop}
                sequential_control c [descend c $depth] $kind $label $matching
            } else {
                fail c UNEXPECTED_STATEMENT_HEADER [list found $marker opener $first]
            }
        }
        entity - component - configuration {
            if {$phase ne "concurrent" || $label eq {}} {fail c UNSAFE_UNIT_BOUNDARY [list found $first]}
            opaque_item c
        }
        architecture - package - context {fail c UNSAFE_UNIT_BOUNDARY [list found $first]}
        else - elsif - when {fail c UNEXPECTED_ALTERNATIVE [list found $first]}
        default {opaque_item c}
    }
    return {}
}

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
            statement c $depth sequential
        }
    }
    return [terminator c $kind $name 1 $matching]
}

proc ::vhdl_index::parser::consume_group {state} {
    upvar 1 $state c
    expect c (
    # Scan with ')' as a stop at relative depth zero.
    if {[boundary c {) {;} end begin}] ne ")"} {fail c UNCLOSED_DELIMITER}
    expect c )
}

proc ::vhdl_index::parser::scope {state kind name depth beginPolicy {ownership {}}} {
    upvar 1 $state c
    set phase declare
    set entityScope [expr {$kind eq "entity"}]
    set entityHeader $entityScope
    set owner {}
    if {$ownership ne {}} {
        lassign $ownership owner parent
        set declarationStart [lindex [span c previous] 1]
        set declarationEnd {}
        set firstScope [llength $c(declarationScopes)]
        set firstIssue [llength $c(objectDiagnostics)]
        set firstTypeIssue [llength $c(typeDiagnostics)]
        set entries {}
        set types {}
        set typeStatus parsed
        set opaque {}
        set gaps {}
        set objectStatus parsed
    }
    while {1} {
        set next [peek c]
        if {$next eq "end"} {
            if {$beginPolicy eq "require" && $phase eq "declare"} {fail c MISSING_BEGIN}
            if {$owner eq {}} {return [terminator c $kind $name]}
            if {$declarationEnd eq {}} {set declarationEnd [lindex [span c] 0]}
            set before [llength $c(diagnostics)]
            set tail [terminator c $kind $name]
            if {[llength $c(diagnostics)] != $before} {
                set c(declarationScopes) [lrange $c(declarationScopes) 0 [expr {$firstScope - 1}]]
                set c(objectDiagnostics) [lrange $c(objectDiagnostics) 0 [expr {$firstIssue - 1}]]
                set c(typeDiagnostics) [lrange $c(typeDiagnostics) 0 [expr {$firstTypeIssue - 1}]]
                set cause [lindex $c(diagnostics) end]
                set affected [list $owner [lindex $tail 1]]
                lappend c(objectDiagnostics) [unproven_scope OBJECT $affected $cause]
                lappend c(typeDiagnostics) [unproven_scope TYPE $affected $cause]
                set objectStatus unrecognized
                set typeStatus unrecognized
                set entries {}
                set types {}
                set opaque {}
                set gaps {}
            }
            if {$parent ne {} || $objectStatus ne "parsed" || $entries ne {} || $opaque ne {} ||
                $types ne {} || $typeStatus ne "parsed" || $gaps ne {} ||
                [llength $c(declarationScopes)] != $firstScope} {
                lappend c(declarationScopes) [dict create id $owner parent_id $parent kind $kind \
                    name_span [lindex $name 1] span [list $owner [lindex $tail 1]] \
                    declarative_span [list $declarationStart $declarationEnd] entries $entries \
                    opaque $opaque gaps $gaps status $objectStatus types $types type_status $typeStatus]
            }
            return $tail
        }
        if {$next eq "begin"} {
            if {$beginPolicy eq "forbid" || $phase ne "declare"} {fail c UNEXPECTED_BEGIN}
            if {$owner ne {}} {set declarationEnd [lindex [span c] 0]}
            incr c(i)
            if {$kind in {process procedure function}} {
                set phase sequential
            } else {
                set phase concurrent
            }
        } elseif {$phase eq "declare"} {
            set split {}
            if {$entityScope && $next eq "identifier"} {
                set split [::vhdl_index::interface::split_keyword c]
            }
            if {$entityScope && ($next in {generic port} || $split ne {})} {
                set first $c(i)
                set c(interfacePending) [span c]
                declaration c $depth
                lappend c(interfaceSites) [list $first $c(i) $entityHeader $split]
                set c(interfacePending) {}
            } else {
                set entityHeader 0
                if {$owner eq {}} {
                    declaration c $depth
                    continue
                }
                set first $c(i)
                set family [::vhdl_index::grammar::declaration_family $next]
                if {$family eq "object"} {
                    opaque_item c object
                    set started [clock microseconds]
                    lassign [::vhdl_index::object::index c $kind $owner $first] records state
                    ::vhdl_index::object::append_entries entries $records
                    if {$state ne "parsed"} {
                        set objectStatus [::vhdl_index::grammar::combine $objectStatus $state]
                        if {$state eq "unrecognized"} {
                            lappend gaps [list uncertain_opaque_item [dict get [lindex $records 0 2] span]]
                            set typeStatus unrecognized
                        }
                    }
                    incr c(objectTime) [expr {[clock microseconds] - $started}]
                } else {
                    set start [lindex [span c] 0]
                    set prior [llength $c(diagnostics)]
                    set category [declaration c $depth $owner]
                    set region [list $start [lindex [span c previous] 1]]
                    if {$category ne {}} {
                        lappend opaque [list $next $region]
                    }
                    if {$family eq "type"} {
                        set started [clock microseconds]
                        set item [::vhdl_index::type_declaration::index c $kind $owner $first $region \
                            $category [lindex $c(diagnostics) $prior]]
                        lappend types $item
                        if {[dict get $item status] ne "parsed"} {
                            set typeStatus [::vhdl_index::grammar::combine $typeStatus [dict get $item status]]
                        }
                        incr c(typeTime) [expr {[clock microseconds] - $started}]
                    }
                    if {[llength $c(diagnostics)] != $prior && $category ne {}} {
                        lappend gaps [list $category $region]
                        set objectStatus unrecognized
                        set typeStatus unrecognized
                    } elseif {$category in {package protected_body}} {
                        lappend gaps [list $category $region]
                        set objectStatus [::vhdl_index::grammar::combine $objectStatus recognized-but-unsupported]
                        set typeStatus [::vhdl_index::grammar::combine $typeStatus recognized-but-unsupported]
                    } elseif {$category ni {{} alias attribute component disconnect file for generic group impure
                        function procedure pure signal subtype type units record protected use}} {
                        lappend gaps [list $category $region]
                        set objectStatus unrecognized
                        set typeStatus unrecognized
                    }
                }
            }
        } else {
            if {$owner ne {}} {set start [lindex [span c] 0]}
            set category [statement c $depth $phase $owner]
            if {$owner ne {} && $category ne {}} {
                lappend gaps [list $category [list $start [lindex [span c previous] 1]]]
                set objectStatus [::vhdl_index::grammar::combine $objectStatus recognized-but-unsupported]
                set typeStatus [::vhdl_index::grammar::combine $typeStatus recognized-but-unsupported]
            }
        }
    }
}

proc ::vhdl_index::parser::unit {state pending} {
    upvar 1 $state c
    set count [llength $c(diagnostics)]
    lassign [header c] kind name head target
    set internal {}
    set status parsed
    set opaque {}
    if {$kind eq "entity"} {set c(interfaceSites) {}}
    if {$kind eq "package" && [peek c] eq "new"} {
        set kind package_instantiation
        set tail [instantiation c]
        set status recognized-but-unsupported
    } elseif {$kind eq "context"} {
        while {[is_context_item c]} {lappend internal [context_item c]}
        set tail [terminator c $kind $name]
    } else {
        if {$kind eq "configuration"} {
            while {[peek c] in {use attribute group}} {opaque_item c}
            if {[peek c] ne "for"} {fail c MISSING_BLOCK_CONFIGURATION}
            configuration_block c 1
            set tail [terminator c $kind $name]
        } else {
            set policy [dict get {architecture require entity allow package forbid package_body forbid} $kind]
            set tail [scope c $kind $name 1 $policy [list [lindex $head 0] {}]]
        }
    }
    if {$kind ne "context" && [lindex $head 1] < [lindex $tail 0]} {
        set opaque [list [lindex $head 1] [lindex $tail 0]]
    }
    if {[llength $c(diagnostics)] > $count} {set status malformed}
    lassign $name spelling extent
    set result [dict create kind $kind name $spelling name_span $extent \
        span [list [lindex $head 0] [lindex $tail 1]] header_span $head terminator_span $tail \
        status $status context $pending context_items $internal opaque $opaque]
    if {$target ne {}} {
        dict set result target [lindex $target 0]
        dict set result target_span [lindex $target 1]
    }
    if {$kind eq "entity" && $c(interfaceSites) ne {}} {
        set started [clock microseconds]
        set owner [::vhdl_index::interface::index_entity c $result $c(interfaceSites)]
        incr c(interfaceTime) [expr {[clock microseconds] - $started}]
        lappend c(interfaces) $owner
        lappend c(interfaceDiagnostics) {*}[dict get $owner diagnostics]
        set c(interfaceStatus) [::vhdl_index::grammar::combine $c(interfaceStatus) [dict get $owner status]]
    }
    return $result
}

proc ::vhdl_index::parser::unproven_scope {domain region cause} {
    return [dict create code ${domain}_UNPROVEN_SCOPE severity error phase structural span $region \
        related_span [dict get $cause span] cause [dict get $cause code]]
}

proc ::vhdl_index::parser::structure {snapshot tape edition limits} {
    variable ::vhdl_index::lexer::labels
    variable ::vhdl_index::lexer::symbols
    array set c [list snapshot $snapshot labels $labels symbols $symbols edition $edition i 0 diagnostics {}]
    foreach key {scopes delimiters} {set c($key) [dict get $limits $key]}
    foreach key {kinds starts significant} {set c($key) [dict get $tape $key]}
    set c(unitTriggers) {}
    foreach {opener connector} {entity is architecture of configuration of package is context is} {
        dict set c(unitTriggers) [dict get $symbols $opener] [dict get $symbols $connector]
    }
    set c(declarationKinds) {}
    dict for {keyword family} $::vhdl_index::grammar::declarationFamilies {
        dict set c(declarationKinds) [dict get $symbols $keyword] $family
    }
    set c(pairs) {}
    set c(closers) {}
    foreach {left right} {( ) {[} {]} << >>} {
        set closer [dict get $symbols $right]
        dict set c(pairs) [dict get $symbols $left] $closer
        lappend c(closers) $closer
    }

    array set c [list interfaces {} interfaceDiagnostics {} interfaceStatus parsed interfaceTime 0         interfacePending {} interfaceLexical [dict get $tape diagnostics] interfaceLexicalAt 0]
    array set c [list declarationScopes {} objectDiagnostics {} objectTime 0 \
        declarationLexical [dict get $tape diagnostics] objectLexicalAt 0 \
        typeDiagnostics {} typeTime 0 typeLexicalAt 0]
    set units {}
    set pending {}
    set recovery {}
    while {[peek c] ne "eof"} {
        set begin [lindex [span c] 0]
        set compound [is_context_item c]
        if {$compound} {
            set status [catch {context_item c} item options]
        } else {
            set firstScope [llength $c(declarationScopes)]
            set firstIssue [llength $c(objectDiagnostics)]
            set firstTypeIssue [llength $c(typeDiagnostics)]
            set status [catch {unit c $pending} item options]
        }
        if {$status} {
            if {[dict get $options -errorcode] ne {VHDL_INDEX STRUCTURE}} {
                return -options $options $item
            }
            lappend c(diagnostics) $item
            set recovery [list $begin [dict get $snapshot length]]
            set c(interfaceStatus) unrecognized
            if {!$compound} {
                set c(declarationScopes) [lrange $c(declarationScopes) 0 [expr {$firstScope - 1}]]
                set c(objectDiagnostics) [lrange $c(objectDiagnostics) 0 [expr {$firstIssue - 1}]]
                set c(typeDiagnostics) [lrange $c(typeDiagnostics) 0 [expr {$firstTypeIssue - 1}]]
            }
            lappend c(objectDiagnostics) [unproven_scope OBJECT $recovery $item]
            lappend c(typeDiagnostics) [unproven_scope TYPE $recovery $item]
            if {$c(interfacePending) ne {}} {
                lappend c(interfaceDiagnostics) [dict create code INTERFACE_UNPROVEN_SCOPE severity error                     span $c(interfacePending) related_span [dict get $item span] cause [dict get $item code]]
            }
            break
        }
        if {$compound} {
            lappend pending $item
        } else {
            lappend units $item
            set pending {}
        }
    }
    if {$pending ne {}} {
        lappend c(diagnostics) [dict create code DANGLING_CONTEXT severity error \
            span [list [lindex [dict get [lindex $pending 0] span] 0] \
                [lindex [dict get [lindex $pending end] span] 1]]]
    }
    set objectStatus parsed
    set typeStatus parsed
    if {$recovery ne {}} {
        set objectStatus unrecognized
        set typeStatus unrecognized
    }
    foreach scope $c(declarationScopes) {
        set objectStatus [::vhdl_index::grammar::combine $objectStatus [dict get $scope status]]
        set typeStatus [::vhdl_index::grammar::combine $typeStatus [dict get $scope type_status]]
    }
    set scopes [lsort -integer -index 1 $c(declarationScopes)]
    return [dict create object_declarations $scopes \
        object_diagnostics $c(objectDiagnostics) object_status $objectStatus object_time_us $c(objectTime) \
        type_diagnostics $c(typeDiagnostics) type_status $typeStatus type_time_us $c(typeTime) \
        units $units structural_diagnostics $c(diagnostics) recovery $recovery \
        unowned_context $pending entity_interfaces $c(interfaces) interface_diagnostics $c(interfaceDiagnostics)         interface_status $c(interfaceStatus) interface_time_us $c(interfaceTime)]
}
