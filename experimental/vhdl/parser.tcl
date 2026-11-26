# Context clauses retain diagnostics inside a proved semicolon fence.
proc ::vhdl_index::parser::context_item {state} {
    upvar 1 $state c
    set kind [peek c]
    set start [lindex [take c] 0]
    set c(grammarFence) [llength $c(significant)]
    set c(grammarDomain) CONTEXT
    set issues {}
    set status [catch {::vhdl_index::grammar::context_names c $kind issues} names options]
    if {$status} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX CONTEXT}} {
            return -options $options $names
        }
        if {$kind eq "use" && [peek c] eq ";"} {
            lappend issues $names
            set names {{} {}}
        } elseif {[dict get $names code] eq "CONTEXT_EXPECTED_NAME"} {
            fail c EXPECTED_NAME [list found [peek c]]
        } else {
            expect c .
        }
    }
    expect c {;}
    set row [dict create kind $kind span [list $start [lindex [span c previous] 1]] names [lindex $names 0]]
    if {$issues ne {}} {
        dict set row status malformed
        dict set row diagnostics $issues
    }
    return $row
}

proc ::vhdl_index::parser::is_context_item {state} {
    upvar 1 $state c
    set kind [peek c]
    return [expr {$kind in {library use} || ($kind eq "context" && [peek c 2] ne "is")}]
}

proc ::vhdl_index::parser::terminator {state kind name {allowName 1} {matching 0} {recoverTypedSeparator 0}} {
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
    if {$recoverTypedSeparator && [peek c] ne ";"} {
        set next [peek c]
        if {$next in {end begin} ||
            ([::vhdl_index::grammar::declaration_family $next] ne {} &&
             [::vhdl_index::grammar::declaration_start c object] eq "safe")} {
            return [list $start [lindex [span c previous] 1]]
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
        if {$kind eq "configuration" && [peek c] eq "."} {
            set targetStart [lindex [lindex $target 1] 0]
            while {[accept c .]} {read_name c}
            set targetSpan [list $targetStart [lindex [span c previous] 1]]
            set target [list [::vhdl_index::slice $c(snapshot) $targetSpan] $targetSpan]
        }
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

# Collect member fences with the common delimiter walk. A declaration
# opener inside a record or units clause is evidence of a lost boundary.
proc ::vhdl_index::parser::type_member_boundary {state kind name} {
    upvar 1 $state c
    set sites {}
    set obscured {}
    while {[peek c] ne "end"} {
        set first $c(i)
        set marker [boundary c {{;} end begin} opaque_tail]
        if {$marker eq "begin"} {fail c UNEXPECTED_BEGIN}
        if {$obscured eq {}} {set obscured $c(opaqueBoundary)}
        set separated [expr {$marker eq ";"}]
        if {$separated} {incr c(i)}
        lappend sites [list $first $c(i) $separated]
    }
    terminator c $kind $name 1 0 1
    if {$obscured ne {}} {
        set c(opaqueBoundary) $obscured
        opaque_object_boundary c 1
        return uncertain_opaque_item
    }
    set c(typeMemberSites) $sites
    return $kind
}

# Child phases use the same counters. Subtract their recorded work before
# attributing the remaining traversal time to this envelope.
proc ::vhdl_index::parser::scope_clock {state} {
    upvar 1 $state c
    return [expr {[clock microseconds] - $c(objectTime) - $c(typeTime) -
        $c(subprogramTime) - $c(declarativeTime) - $c(withdrawalTime) - $c(bodyBoundaryTime) - $c(protectedTime)}]
}

proc ::vhdl_index::parser::indexed_declaration {state owner ownerKind family} {
    upvar 1 $state c
    set first $c(i)
    switch -- $family {
        attribute {set context attribute_item}
        configuration_specification {set context configuration_specification}
        default {set context indexed_item}
    }
    set stops {{;} end begin}
    if {$ownerKind eq "configuration"} {lappend stops for}
    set marker [boundary c $stops $context]
    set fence $c(i)
    set terminator {}
    if {$marker eq ";"} {set terminator [take c]}
    set started [clock microseconds]
    set record [::vhdl_index::declarative::index c $owner $ownerKind $family $first $fence $terminator $c(opaqueBoundary)]
    incr c(declarativeTime) [expr {[clock microseconds] - $started}]
    return $record
}

proc ::vhdl_index::parser::indexed_configuration {state owner ownerKind} {
    upvar 1 $state c
    set row [indexed_declaration c $owner $ownerKind configuration_specification]
    set separator [dict get $row terminator_span]
    dict set row binding_terminator_span $separator
    set units {}
    if {$separator ne {} && $c(edition) >= 2008} {
        while {[peek c] eq "use" && [peek c 1] eq "vunit"} {
            set start [lindex [span c] 0]
            opaque_item c configuration_specification
            lappend units [list $start [lindex [span c previous] 1]]
        }
    }
    if {$units ne {}} {
        dict set row verification_unit_binding_spans $units
        dict set row status [::vhdl_index::grammar::combine [dict get $row status] recognized-but-unsupported]
        dict lappend row diagnostics [diagnostic c UNSUPPORTED_VERIFICATION_UNIT_BINDING [list span [lindex $units 0]]]
        dict set row span [list [lindex [dict get $row span] 0] [lindex $units end 1]]
        dict set row terminator_span {}
    }
    if {[peek c] eq "end" && [peek c 1] eq "for"} {
        set tail [terminator c for {} 0 0 1]
        dict set row end_for_span $tail
        dict set row span [list [lindex [dict get $row span] 0] [lindex $tail 1]]
        if {[peek c -1] eq ";"} {
            dict set row terminator_span [span c previous]
        } else {
            dict set row terminator_span {}
            dict set row status [::vhdl_index::grammar::combine [dict get $row status] malformed]
            dict lappend row diagnostics [diagnostic c CONFIGURATION_SPECIFICATION_MISSING_END_SEPARATOR {}]
        }
        if {$c(edition) < 2008} {
            dict set row status [::vhdl_index::grammar::combine [dict get $row status] recognized-but-unsupported]
            dict lappend row diagnostics [diagnostic c EDITION_CONFIGURATION_SPECIFICATION_END [list span $tail]]
        }
    } elseif {$units ne {}} {
        dict set row status [::vhdl_index::grammar::combine [dict get $row status] malformed]
        dict lappend row diagnostics [diagnostic c CONFIGURATION_SPECIFICATION_EXPECTED_END_FOR {}]
    }
    return $row
}

proc ::vhdl_index::parser::protected_member_allowed {state ownerKind} {
    upvar 1 $state c
    set next [peek c]
    if {$ownerKind eq "protected"} {
        return [expr {$next in {function procedure pure impure use attribute}}]
    }
    return [expr {$next in {function procedure pure impure package type subtype constant
        variable file alias attribute use group}}]
}

proc ::vhdl_index::parser::declaration {state depth {owner {}} {recordVar {}} {ownerKind {}} {typeShapeVar {}}} {
    upvar 1 $state c
    set first [peek c]
    set observe [expr {$owner ne {}}]
    set headerContext [expr {$observe ? "opaque_tail" : ""}]
    set itemContext [expr {$observe ? "opaque_item" : ""}]
    switch -- $first {
        impure - pure - function - procedure {
            if {$observe} {
                upvar 1 $recordVar subprogram
                set firstSpec $c(i)
                set opening [lindex [span c] 0]
                set headerContext subprogram_header
            }
            if {$first in {impure pure}} {incr c(i)}
            set kind [peek c]
            if {$kind ni {function procedure}} {fail c EXPECTED_SUBPROGRAM}
            incr c(i)
            set name [read_name c 1]
            set marker [boundary c {is {;} end begin} $headerContext]
            set fence $c(i)
            set obscured [opaque_object_boundary c $observe]
            set index [expr {$observe && !$obscured}]
            if {$marker eq "is"} {
                set is [take c]
                if {[peek c] ne "new"} {
                    set child {}
                    if {$index} {
                        set subprogram [::vhdl_index::subprogram::index c $owner $firstSpec $fence body $is]
                    }
                    set nextDepth [descend c $depth]
                    if {$index && $ownerKind ne "protected"} {
                        set child [list $opening $owner]
                        set formals {}
                        if {[dict get $subprogram status] eq "parsed" && [dict exists $subprogram parameters]} {
                            set formals [dict get $subprogram parameters]
                        }
                        set boundaryStarted [scope_clock c]
                        set tail [scope c $kind $name $nextDepth require $child shape $formals]
                        incr c(bodyBoundaryTime) [expr {[scope_clock c] - $boundaryStarted}]
                        dict set subprogram span [list $opening [lindex $tail 1]]
                        dict set subprogram terminator_span $tail
                        set subprogram [dict merge $subprogram $shape]
                        if {$ownerKind eq "package"} {
                            dict set subprogram body_status [::vhdl_index::grammar::combine \
                                [dict get $subprogram body_status] malformed]
                            dict lappend subprogram body_diagnostics [dict create code SUBPROGRAM_BODY_OUT_OF_CONTEXT \
                                severity error span $is]
                        }
                    } else {
                        set tail [scope c $kind $name $nextDepth require]
                        if {$index} {
                            dict set subprogram span [list $opening [lindex $tail 1]]
                            dict set subprogram terminator_span $tail
                            dict set subprogram body_status malformed
                            dict set subprogram body_diagnostics [list [dict create code SUBPROGRAM_BODY_OUT_OF_CONTEXT \
                                severity error span $is]]
                        }
                    }
                    if {$obscured} {return uncertain_opaque_item}
                    return {}
                }
                if {$c(edition) < 2008} {fail c EDITION_SUBPROGRAM_INSTANTIATION}
                opaque_item c
                if {$index} {
                    set tail {}
                    set fence $c(i)
                    if {[peek c -1] eq ";"} {
                        set tail [span c previous]
                        incr fence -1
                    }
                    set subprogram [::vhdl_index::subprogram::index c $owner $firstSpec $fence instantiation $tail]
                }
            } elseif {$marker in {{;} declaration} ||
                ($marker eq "end" && $ownerKind in {protected protected_body} && [peek c 1] eq "protected")} {
                set tail {}
                if {$marker eq ";"} {set tail [take c]}
                if {$index} {
                    set subprogram [::vhdl_index::subprogram::index c $owner $firstSpec $fence declaration $tail]
                }
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
                    set child [descend c $depth]
                    if {$type eq "record" && $observe} {return [type_member_boundary c record $name]}
                    if {$observe && $type ne "record" && $name ne {} && !($type eq "protected_body" && $ownerKind eq "package")} {
                        upvar 1 $typeShapeVar typeShape
                        set protectedStarted [scope_clock c]
                        set saved $c(i)
                        set c(i) $firstType
                        set memberOwner [lindex [span c] 0]
                        set c(i) $saved
                        scope c $type $name $child forbid [list $memberOwner $owner] typeShape
                        incr c(protectedTime) [expr {[scope_clock c] - $protectedStarted}]
                    } else {
                        scope c $type $name $child forbid
                    }
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
                    set child [descend c $depth]
                    if {$observe && !$obscured} {return [type_member_boundary c units $name]}
                    scope c units $name $child forbid
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

proc ::vhdl_index::parser::configuration_block {state depth owner} {
    upvar 1 $state c
    set child [descend c $depth]
    expect c for
    set start $c(i)
    set marker [boundary c {for end use {;}}]
    if {$start == $c(i)} {fail c INCOMPLETE_CONFIGURATION_HEADER}
    if {$marker eq ";"} {incr c(i)}
    configuration_part c $child $owner
    terminator c for {} 0
}

# Configuration for-headers end before the first child, use binding or end.
proc ::vhdl_index::parser::configuration_part {state depth owner} {
    upvar 1 $state c
    while {[peek c] ne "end"} {
        set next [peek c]
        if {$next eq "for"} {
            configuration_block c $depth $owner
        } elseif {$next in {use attribute group}} {
            set start [lindex [span c] 0]
            set keyword [peek c 1]
            opaque_item c
            set kind {}
            if {$next eq "use" && $keyword ni {entity configuration open vunit}} {
                set kind local_use_clauses
            } elseif {$next eq "attribute"} {
                set kind attribute_declarations
            } elseif {$next eq "group"} {
                set kind group_declarations
            }
            if {$kind ne {}} {
                note_gap c configuration_block_item [list $start [lindex [span c previous] 1]] \
                    recognized-but-unsupported [list $kind] $owner
            }
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

proc ::vhdl_index::parser::scope {state kind name depth beginPolicy {ownership {}} {shapeVar {}} {formals {}}} {
    upvar 1 $state c
    if {$shapeVar ne {}} {
        upvar 1 $shapeVar shape
        set shape {}
        set begin {}
    }
    set protectedScope [expr {$kind in {protected protected_body}}]
    set memberIssues {}
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
        set firstWithdrawal [llength $c(withdrawnScopes)]
        set firstGap [llength $c(coverageGaps)]
        set entries {}
        set types {}
        set subprograms {}
        set declarations {}
        set typeStatus parsed
        set opaque {}
        set gaps {}
        set objectStatus parsed
    }
    while {1} {
        set next [peek c]
        if {$next eq "end"} {
            if {$kind eq "configuration" && $phase ne "configuration_end"} {fail c MISSING_BLOCK_CONFIGURATION}
            if {$beginPolicy eq "require" && $phase eq "declare"} {fail c MISSING_BEGIN}
            if {$owner eq {}} {return [terminator c $kind $name]}
            if {$declarationEnd eq {}} {set declarationEnd [lindex [span c] 0]}
            set before [llength $c(diagnostics)]
            set endOrdinal $c(i)
            set tail [terminator c $kind $name]
            if {$shapeVar ne {} && $protectedScope} {
                set closeName {}
                set endKeywords [expr {$kind eq "protected_body" ? 3 : 2}]
                if {$c(i) - $endOrdinal == $endKeywords + 2} {
                    incr c(i) -1
                    set closeName [span c previous]
                    incr c(i)
                }
                if {[llength $c(diagnostics)] == $before} {
                    set memberStatus [::vhdl_index::grammar::combine $objectStatus $typeStatus]
                    foreach item $declarations {
                        set memberStatus [::vhdl_index::grammar::combine $memberStatus [dict get $item status]]
                        lappend memberIssues {*}[dict get $item diagnostics]
                    }
                    foreach item $subprograms {
                        set memberStatus [::vhdl_index::grammar::combine $memberStatus [dict get $item status]]
                        lappend memberIssues {*}[dict get $item diagnostics]
                        if {[dict exists $item body_status]} {
                            set memberStatus [::vhdl_index::grammar::combine $memberStatus [dict get $item body_status]]
                            lappend memberIssues {*}[dict get $item body_diagnostics]
                        }
                    }
                    set shape [dict create member_scope_id $owner member_span [list $declarationStart $declarationEnd] \
                        end_name_span $closeName protected_terminator_span $tail \
                        member_status $memberStatus diagnostics $memberIssues]
                }
            } elseif {$shapeVar ne {}} {
                if {[llength $c(diagnostics)] == $before} {
                    set shape [dict create body_scope_id $owner parent_scope_id $parent body_status parsed \
                        body_diagnostics {} declarative_span [list $declarationStart $declarationEnd] \
                        begin_span $begin sequential_span [list [lindex $begin 1] [lindex $tail 0]]]
                } else {
                    set issue [unproven_scope SUBPROGRAM [list $owner [lindex $tail 1]] [lindex $c(diagnostics) end]]
                    set shape [dict create body_status unrecognized body_diagnostics [list $issue]]
                }
            }
            if {[llength $c(diagnostics)] != $before} {
                set cause [lindex $c(diagnostics) end]
                set affected [list $owner [lindex $tail 1]]
                set loss [compose_withdrawal c $kind $affected $cause $parent $firstScope $firstGap $firstWithdrawal $declarations]
                trim_suffix c declarationScopes $firstScope
                trim_suffix c objectDiagnostics $firstIssue
                trim_suffix c typeDiagnostics $firstTypeIssue
                lappend c(withdrawnScopes) $loss
                if {$entityScope} {set c(interfaceSites) {}}
                if {$kind ne "configuration"} {
                    lappend c(objectDiagnostics) [unproven_scope OBJECT $affected $cause]
                    lappend c(typeDiagnostics) [unproven_scope TYPE $affected $cause]
                    set objectStatus unrecognized
                    set typeStatus unrecognized
                }
                set entries {}
                set types {}
                set subprograms {}
                set declarations {}
                set formals {}
                set opaque {}
                set gaps {}
            }
            if {$shapeVar ne {} && [llength $c(diagnostics)] != $before} {
                return $tail
            }
            if {$kind eq "configuration" || $parent ne {} || $objectStatus ne "parsed" || $entries ne {} || $opaque ne {} ||
                $types ne {} || $subprograms ne {} || $declarations ne {} || $typeStatus ne "parsed" || $gaps ne {} ||
                [llength $c(declarationScopes)] != $firstScope} {
                set record [dict create id $owner parent_id $parent kind $kind \
                    name_span [lindex $name 1] span [list $owner [lindex $tail 1]] \
                    declarative_span [list $declarationStart $declarationEnd] entries $entries \
                    opaque $opaque gaps $gaps status $objectStatus types $types type_status $typeStatus]
                if {$subprograms ne {}} {dict set record subprograms $subprograms}
                if {$declarations ne {}} {dict set record declarations $declarations}
                if {$formals ne {}} {dict set record formal_parameters $formals}
                lappend c(declarationScopes) $record
            } else {
                dict set c(emptyRegions) $owner [list $declarationStart $declarationEnd]
            }
            return $tail
        }
        if {$phase eq "configuration_end"} {fail c EXPECTED_CONFIGURATION_END}
        if {$kind eq "configuration" && $next eq "for"} {
            set declarationEnd [lindex [span c] 0]
            configuration_block c $depth $owner
            note_gap c configuration_block [list $declarationEnd [lindex [span c previous] 1]] \
                recognized-but-unsupported {configuration_blocks} $owner
            set phase configuration_end
        } elseif {$next eq "begin"} {
            if {$beginPolicy eq "forbid" || $phase ne "declare"} {fail c UNEXPECTED_BEGIN}
            if {$owner ne {}} {set declarationEnd [lindex [span c] 0]}
            if {$shapeVar ne {}} {set begin [span c]}
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
                if {$kind eq "configuration" && $next ni {use attribute group}} {
                    fail c EXPECTED_CONFIGURATION_ITEM [list found $next]
                }
                if {$kind eq "configuration" && $next eq "use" && [peek c 1] eq "vunit"} {
                    set start [lindex [span c] 0]
                    opaque_item c indexed_item
                    set region [list $start [lindex [span c previous] 1]]
                    lappend opaque [list $next $region]
                    note_gap c verification_unit_binding $region recognized-but-unsupported {configuration_blocks} $owner
                } elseif {$protectedScope && $family ne {} && ![protected_member_allowed c $kind]} {
                    set start [lindex [span c] 0]
                    if {$family eq "object"} {
                        opaque_item c object
                    } else {
                        declaration c $depth
                    }
                    set region [list $start [lindex [span c previous] 1]]
                    lappend opaque [list $next $region]
                    lappend gaps [list protected_member_out_of_context $region]
                    lappend memberIssues [::vhdl_index::type_declaration::at TYPE_PROTECTED_MEMBER_OUT_OF_CONTEXT $region]
                    set objectStatus [::vhdl_index::grammar::combine $objectStatus malformed]
                    set typeStatus [::vhdl_index::grammar::combine $typeStatus malformed]
                } elseif {$family eq "component"} {
                    set started [clock microseconds]
                    set row [::vhdl_index::declarative::component c $depth $owner $kind]
                    incr c(declarativeTime) [expr {[clock microseconds] - $started}]
                    lappend declarations $row
                    lappend opaque [list component [dict get $row span]]
                } elseif {$family in {alias attribute file_object group disconnect local_use configuration_specification}} {
                    if {$family eq "configuration_specification"} {
                        set row [indexed_configuration c $owner $kind]
                    } else {
                        set row [indexed_declaration c $owner $kind $family]
                    }
                    lappend declarations $row
                    lappend opaque [list $next [dict get $row span]]
                    if {[dict get $row status] eq "unrecognized"} {
                        if {$kind ne "configuration"} {
                            opaque_object_boundary c 1
                            set objectStatus unrecognized
                            set typeStatus unrecognized
                        }
                        scope_gap c gaps $owner $kind uncertain_opaque_item [dict get $row span] unrecognized
                    }
                } elseif {$family eq "object"} {
                    opaque_item c object
                    set started [clock microseconds]
                    lassign [::vhdl_index::object::index c $kind $owner $first] records state
                    ::vhdl_index::object::append_entries entries $records
                    if {$state ne "parsed"} {
                        set objectStatus [::vhdl_index::grammar::combine $objectStatus $state]
                        if {$state eq "unrecognized"} {
                            scope_gap c gaps $owner $kind uncertain_opaque_item [dict get [lindex $records 0 2] span] unrecognized
                            set typeStatus unrecognized
                        }
                    }
                    incr c(objectTime) [expr {[clock microseconds] - $started}]
                } else {
                    set start [lindex [span c] 0]
                    set prior [llength $c(diagnostics)]
                    set subprogram {}
                    set typeShape {}
                    set category [declaration c $depth $owner subprogram $kind typeShape]
                    if {$subprogram ne {}} {lappend subprograms $subprogram}
                    set region [list $start [lindex [span c previous] 1]]
                    if {$category ne {}} {
                        lappend opaque [list $next $region]
                    }
                    if {$family eq "type"} {
                        set started [clock microseconds]
                        set item [::vhdl_index::type_declaration::index c $kind $owner $first $region \
                            $category [lindex $c(diagnostics) $prior] $typeShape]
                        lappend types $item
                        if {[dict get $item status] ne "parsed"} {
                            set typeStatus [::vhdl_index::grammar::combine $typeStatus [dict get $item status]]
                        }
                        incr c(typeTime) [expr {[clock microseconds] - $started}]
                    }
                    if {[llength $c(diagnostics)] != $prior && $category in {protected protected_body}} {
                        # The withdrawn member region carries its own capability mask.
                    } elseif {[llength $c(diagnostics)] != $prior && $category ne {}} {
                        scope_gap c gaps $owner $kind $category $region unrecognized
                        set objectStatus unrecognized
                        set typeStatus unrecognized
                    } elseif {$category eq "package" || ($category eq "protected_body" && $typeShape eq {})} {
                        scope_gap c gaps $owner $kind $category $region recognized-but-unsupported
                        set objectStatus [::vhdl_index::grammar::combine $objectStatus recognized-but-unsupported]
                        set typeStatus [::vhdl_index::grammar::combine $typeStatus recognized-but-unsupported]
                    } elseif {$category ni {{} alias attribute component disconnect file for generic group impure
                        function procedure pure signal subtype type units record protected protected_body use}} {
                        scope_gap c gaps $owner $kind $category $region unrecognized
                        set objectStatus unrecognized
                        set typeStatus unrecognized
                    }
                }
            }
        } else {
            if {$owner ne {}} {set start [lindex [span c] 0]}
            set category [statement c $depth $phase $owner]
            if {$owner ne {} && $category ne {}} {
                scope_gap c gaps $owner $kind $category [list $start [lindex [span c previous] 1]] \
                    recognized-but-unsupported
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
        set policy [dict get {architecture require entity allow package forbid package_body forbid configuration forbid} $kind]
        set tail [scope c $kind $name 1 $policy [list [lindex $head 0] {}]]
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
        set owner [::vhdl_index::interface::index_owner c $result $c(interfaceSites)]
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

# The direct profile sets the minimum affected coverage. Descendant claims
# and region gaps contribute their own capabilities independently.
proc ::vhdl_index::parser::region_capabilities {kind} {
    switch -- $kind {
        root {
            return {object_declarations type_declarations subprogram_specifications subprogram_bodies
                alias_declarations attribute_declarations file_objects component_declarations entity_interfaces
                group_templates group_declarations disconnect_specifications local_use_clauses
                configuration_specifications configuration_blocks}
        }
        component {return {component_declarations}}
        protected {return {subprogram_specifications attribute_declarations local_use_clauses}}
        configuration {return {attribute_declarations group_declarations local_use_clauses configuration_blocks}}
    }
    set result {object_declarations type_declarations subprogram_specifications subprogram_bodies
        alias_declarations attribute_declarations file_objects group_templates group_declarations local_use_clauses}
    if {$kind in {architecture package block generate}} {lappend result component_declarations}
    if {$kind in {architecture entity package block generate}} {lappend result disconnect_specifications}
    if {$kind in {architecture block generate}} {lappend result configuration_specifications}
    if {$kind eq "entity"} {lappend result entity_interfaces}
    return $result
}

proc ::vhdl_index::parser::note_gap {state kind region status capabilities owner} {
    upvar 1 $state c
    lappend c(coverageGaps) [dict create kind $kind span $region status $status capabilities $capabilities owner_id $owner]
}

proc ::vhdl_index::parser::scope_gap {state gapsVar owner ownerKind kind region status} {
    upvar 1 $state c $gapsVar gaps
    lappend gaps [list $kind $region]
    set profile $ownerKind
    if {$kind in {package block generate protected_body}} {set profile $kind}
    set capabilities [region_capabilities $profile]
    if {$c(edition) >= 2008 &&
        ($kind eq "protected_body" || ($kind eq "uncertain_opaque_item" &&
         $ownerKind in {entity architecture package package_body process function procedure protected_body})) &&
        "component_declarations" ni $capabilities} {
        # A nested package may be hidden inside this bounded opaque span.
        lappend capabilities component_declarations
    }
    # A hidden declarative item cannot take ownership of the separate entity header.
    set capabilities [lsearch -all -inline -not -exact $capabilities entity_interfaces]
    note_gap c $kind $region $status $capabilities $owner
}

proc ::vhdl_index::parser::trim_suffix {state key length} {
    upvar 1 $state c
    if {[llength $c($key)] > $length} {
        set c($key) [lrange $c($key) 0 [expr {$length - 1}]]
    }
}

proc ::vhdl_index::parser::withdrawal {kind region cause parent} {
    return [dict create scope_kind $kind span $region capabilities [region_capabilities $kind] diagnostic $cause parent_id $parent]
}

proc ::vhdl_index::parser::compose_withdrawal {state kind region cause parent firstScope firstGap firstWithdrawal declarations} {
    upvar 1 $state c
    set started [clock microseconds]
    set lost [withdrawal $kind $region $cause $parent]
    set mask {}
    foreach capability [dict get $lost capabilities] {dict set mask $capability 1}
    set contributors [lrange $c(coverageGaps) $firstGap end]
    foreach child [lrange $c(withdrawnScopes) $firstWithdrawal end] {
        if {[dict exists $child contributors]} {
            lappend contributors {*}[dict get $child contributors]
            dict unset child contributors
        }
        dict set child kind [dict get $child scope_kind]
        dict set child status unrecognized
        lappend contributors $child
    }
    foreach child [lrange $c(declarationScopes) $firstScope end] {
        foreach capability [region_capabilities [dict get $child kind]] {dict set mask $capability 1}
        if {[dict exists $child declarations]} {lappend declarations {*}[dict get $child declarations]}
    }
    foreach declaration $declarations {
        foreach capability [::vhdl_index::declaration_capabilities $declaration] {
            dict set mask $capability 1
        }
        if {[dict exists $declaration candidate_forms]} {
            lappend contributors [dict create kind declaration_candidates span [dict get $declaration span] \
                status [dict get $declaration status] capabilities [dict get $declaration candidate_capabilities] \
                forms [dict get $declaration candidate_forms] owner_id [dict get $declaration owner_id] \
                diagnostics [dict get $declaration diagnostics]]
        }
    }
    foreach contributor $contributors {
        foreach capability [dict get $contributor capabilities] {dict set mask $capability 1}
    }
    dict set lost capabilities [dict keys $mask]
    if {$contributors ne {}} {
        dict set lost contributors [lsort -integer -index {3 0} $contributors]
    }
    trim_suffix c coverageGaps $firstGap
    trim_suffix c withdrawnScopes $firstWithdrawal
    incr c(withdrawalTime) [expr {[clock microseconds] - $started}]
    return $lost
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

    array set c [list interfaces {} interfaceDiagnostics {} interfaceStatus parsed interfaceTime 0         interfacePending {} interfaceLexical [dict get $tape diagnostics] interfaceLexicalAt 0 componentLexicalAt 0]
    array set c [list declarationScopes {} emptyRegions {} withdrawnScopes {} coverageGaps {} withdrawalTime 0 objectDiagnostics {} objectTime 0 \
        declarationLexical [dict get $tape diagnostics] objectLexicalAt 0 \
        typeDiagnostics {} typeTime 0 typeLexicalAt 0 subprogramLexicalAt 0 subprogramTime 0 bodyBoundaryTime 0 protectedTime 0 declarativeTime 0 declarativeLexicalAt 0]
    set units {}
    set pending {}
    set recovery {}
    while {[peek c] ne "eof"} {
        set begin [lindex [span c] 0]
        set compound [is_context_item c]
        set firstGap [llength $c(coverageGaps)]
        set firstWithdrawal [llength $c(withdrawnScopes)]
        set firstScope [llength $c(declarationScopes)]
        if {$compound} {
            set status [catch {context_item c} item options]
        } else {
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
            set loss [compose_withdrawal c root $recovery $item {} $firstScope $firstGap $firstWithdrawal {}]
            if {!$compound} {
                trim_suffix c declarationScopes $firstScope
                trim_suffix c objectDiagnostics $firstIssue
                trim_suffix c typeDiagnostics $firstTypeIssue
            }
            lappend c(withdrawnScopes) $loss
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
    set subprogramStatus parsed
    set bodyStatus parsed
    if {$recovery ne {}} {
        set objectStatus unrecognized
        set typeStatus unrecognized
        set subprogramStatus unrecognized
        set bodyStatus unrecognized
    }
    foreach scope $c(declarationScopes) {
        set objectStatus [::vhdl_index::grammar::combine $objectStatus [dict get $scope status]]
        set typeStatus [::vhdl_index::grammar::combine $typeStatus [dict get $scope type_status]]
        if {[dict get $scope gaps] ne {} || [dict get $scope status] eq "unrecognized"} {
            set subprogramStatus [::vhdl_index::grammar::combine $subprogramStatus [dict get $scope status]]
            set bodyStatus [::vhdl_index::grammar::combine $bodyStatus [dict get $scope status]]
        }
        if {[dict exists $scope subprograms]} {
            foreach item [dict get $scope subprograms] {
                set subprogramStatus [::vhdl_index::grammar::combine $subprogramStatus [dict get $item status]]
                if {[dict exists $item body_status]} {
                    set bodyStatus [::vhdl_index::grammar::combine $bodyStatus [dict get $item body_status]]
                }
            }
        }
    }
    set scopes [lsort -integer -index 1 $c(declarationScopes)]
    return [dict create object_declarations $scopes empty_regions $c(emptyRegions) withdrawn_scopes $c(withdrawnScopes) \
        coverage_gaps [lsort -integer -index {3 0} $c(coverageGaps)] withdrawal_time_us $c(withdrawalTime) \
        object_diagnostics $c(objectDiagnostics) object_status $objectStatus object_time_us $c(objectTime) \
        type_diagnostics $c(typeDiagnostics) type_status $typeStatus type_time_us $c(typeTime) \
        subprogram_status $subprogramStatus body_status $bodyStatus subprogram_time_us $c(subprogramTime) \
        declarative_time_us $c(declarativeTime) body_boundary_time_us $c(bodyBoundaryTime) protected_time_us $c(protectedTime) \
        units $units structural_diagnostics $c(diagnostics) recovery $recovery \
        unowned_context $pending entity_interfaces $c(interfaces) interface_diagnostics $c(interfaceDiagnostics)         interface_status $c(interfaceStatus) interface_time_us $c(interfaceTime)]
}
