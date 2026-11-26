# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Interface sites are fenced before running the shared formal grammar.
proc ::vhdl_index::parser::formal_site {state} {
    upvar 1 $state c
    set first $c(i)
    incr c(i)
    if {[peek c] ne "("} {fail c EXPECTED_INTERFACE_GROUP}
    scope_group c INTERFACE 1
    accept c {;}
    return [list $first $c(i) 1 {}]
}

proc ::vhdl_index::parser::scope_group {state domain {recover 0}} {
    upvar 1 $state c
    if {[peek c] ne "("} {fail c EXPECTED_OPEN_GROUP}
    set c(grammarFence) [llength $c(significant)]
    set c(grammarDomain) $domain
    if {[catch {::vhdl_index::grammar::group c $recover} cause options]} {
        if {[dict get $options -errorcode] ne [list VHDL_INDEX $domain]} {
            return -options $options $cause
        }
        return -code error -errorcode {VHDL_INDEX STRUCTURE} $cause
    }
    return $cause
}

proc ::vhdl_index::parser::map_aspect {state form site} {
    upvar 1 $state c
    set keyword [take c]
    set connector [span c]
    expect c map
    set c(grammarFence) [llength $c(significant)]
    set c(grammarDomain) ASSOCIATION
    if {[catch {::vhdl_index::grammar::map_association c $form $site $keyword $connector} details options]} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX ASSOCIATION}} {
            return -options $options $details
        }
        return -code error -errorcode {VHDL_INDEX STRUCTURE} $details
    }
    return $details
}

proc ::vhdl_index::parser::package_header {state name head} {
    upvar 1 $state c
    set shape [dict create header_span $head name [lindex $name 0] interfaces {} generic_map {}]
    if {[peek c] ne "generic"} {return $shape}
    if {[peek c 1] eq "map"} {fail c EXPECTED_GENERIC_CLAUSE}
    set keyword [span c]
    set site [formal_site c]
    if {$c(edition) < 2008} {
        set extent [list [lindex $keyword 0] [lindex [span c previous] 1]]
        set issue [diagnostic c EDITION_PACKAGE_GENERIC [list span $keyword]]
        lappend c(diagnostics) $issue
        dict set shape interfaces [list [dict create kind generic span $extent keyword_span $keyword \
            items {} status recognized-but-unsupported diagnostics [list $issue]]]
    } else {
        set owner [dict create name_span [lindex $name 1] span $head]
        dict set shape interfaces [dict get [::vhdl_index::interface::index_owner c $owner [list $site] scopeLexicalAt] clauses]
    }
    if {[peek c] eq "generic"} {
        set map [map_aspect c generic package_header]
        if {$c(edition) < 2008} {
            dict set map associations {}
            dict set map association_validation recognized-but-unsupported
            dict lappend map association_diagnostics $issue
        }
        set separator [take_semicolon c]
        dict set shape generic_map [dict merge $map [dict create terminator_span $separator]]
    }
    return $shape
}

proc ::vhdl_index::parser::nested_package {state depth owner ownerKind recordVar} {
    upvar 1 $state c $recordVar record
    if {$c(edition) < 2008} {fail c EDITION_NESTED_PACKAGE}
    lassign [header c] kind name head
    if {$kind eq "package_body" && $ownerKind eq "package"} {fail c NESTED_PACKAGE_OUT_OF_CONTEXT}
    set opening [lindex $head 0]
    set details {}
    if {$kind eq "package" && [peek c] eq "new"} {
        set kind package_instantiation
        set tail [instantiation c details]
    } else {
        if {$kind eq "package"} {
            set shape [package_header c $name $head]
        } else {
            set shape [dict create header_span $head name [lindex $name 0]]
        }
        set tail [scope c $kind $name [descend c $depth] forbid [list $opening $owner] {} {} $shape]
        set affected [list $opening [lindex $tail 1]]
        set loss [lindex $c(withdrawnScopes) end]
        if {$loss ne {} && [dict get $loss span] eq $affected} {
            ::vhdl_index::ownership::gap c nested_package_boundary $affected \
                unrecognized {package_declarations} $owner [list [dict get $loss diagnostic]]
            return
        }
    }
    set record [dict merge [dict create kind $kind owner_id $owner name [lindex $name 0] name_span [lindex $name 1] \
        span [list $opening [lindex $tail 1]] header_span $head terminator_span $tail status parsed diagnostics {}] $details]
}

proc ::vhdl_index::parser::scope_closing {state tail begin} {
    upvar 1 $state c
    set name {}
    if {[is_name [peek c -2] 0]} {
        incr c(i) -1
        set name [span c previous]
        incr c(i)
    }
    set concurrent {}
    if {$begin ne {}} {set concurrent [list [lindex $begin 1] [lindex $tail 0]]}
    return [dict create terminator_span $tail end_name_span $name begin_span $begin concurrent_span $concurrent]
}

proc ::vhdl_index::parser::block_statement {state depth owner ownerKind label} {
    upvar 1 $state c
    if {$label eq {}} {fail c MISSING_BLOCK_LABEL}
    if {$ownerKind eq "entity"} {fail c BLOCK_OUT_OF_CONTEXT}
    set opening [lindex $label 1 0]
    set colon [span c previous]
    set keyword [take c]
    set guard {}
    set guardGroup {}
    if {[peek c] eq "("} {
        set open [span c]
        if {[peek c 1] eq ")"} {fail c EMPTY_BLOCK_GUARD}
        scope_group c BLOCK
        set close [span c previous]
        set guard [list [lindex $open 1] [lindex $close 0]]
        set guardGroup [list [lindex $open 0] [lindex $close 1]]
    }
    set connector {}
    if {[peek c] eq "is"} {set connector [take c]}
    set sites {}
    set maps {}
    foreach form {generic port} {
        if {[peek c] ne $form} {continue}
        if {[peek c 1] eq "map"} {fail c BLOCK_MAP_WITHOUT_CLAUSE}
        lappend sites [formal_site c]
        if {[peek c] eq $form && [peek c 1] eq "map"} {
            set map [map_aspect c $form block_header]
            dict set map terminator_span [take_semicolon c]
            lappend maps $map
        }
    }
    if {[peek c] in {generic port}} {fail c BLOCK_INTERFACE_ORDER}
    set head [list $opening [lindex [span c previous] 1]]
    set interfaceOwner [dict create name_span [lindex $label 1] span $head]
    set clauses [dict get [::vhdl_index::interface::index_owner c $interfaceOwner $sites scopeLexicalAt] clauses]
    set syntax [dict create label [lindex $label 0] label_span [lindex $label 1] colon_span $colon \
        block_span $keyword header_span $head guard_span $guard guard_group_span $guardGroup \
        guard_status [expr {$guard eq {} ? "absent" : "opaque"}] is_span $connector interfaces $clauses maps $maps]
    set child {}
    if {$owner ne {}} {set child [list $opening $owner]}
    scope c block $label [descend c $depth] require $child {} {} $syntax
}

# Structural starters cannot occur at top level inside an opaque concurrent
# expression. A missing separator must not hide a local declaration owner.
proc ::vhdl_index::parser::opaque_concurrent {state ownerKind} {
    upvar 1 $state c
    set stops {begin end block process generate elsif}
    set marker [scan c [concat {{;} =>} $stops] {} {} $stops 1]
    if {$marker eq "eof"} {fail c TRUNCATED_SCOPE}
    if {$marker eq ";"} {
        incr c(i)
    } elseif {$marker eq "end" && $ownerKind ni {block generate}} {
        # Preserve the preexisting end-boundary diagnostic on other bodies.
        lappend c(diagnostics) [diagnostic c MISSING_SEMICOLON {}]
    } else {
        fail c UNPROVEN_CONCURRENT_BOUNDARY [list found $marker]
    }
}

# The typed stack prevents a mistaken inner ending from consuming an
# explicitly named ancestor's closing fence.
proc ::vhdl_index::parser::open_named_scope {state kind name} {
    upvar 1 $state c
    set key [list $kind [lindex $name 2]]
    dict incr c(activeNames) $key
    return $key
}

proc ::vhdl_index::parser::close_named_scope {state key} {
    upvar 1 $state c
    dict incr c(activeNames) $key -1
    if {[dict get $c(activeNames) $key] == 0} {
        dict unset c(activeNames) $key
    }
}

proc ::vhdl_index::parser::generate_extent {state stops} {
    upvar 1 $state c
    set first $c(i)
    set start [lindex [span c] 0]
    set marker [boundary c [concat $stops {{;} end begin block process elsif else when generate}]]
    if {$marker ni $stops} {
        fail c INCOMPLETE_GENERATE_HEADER [list expected $stops found $marker]
    }
    if {$first == $c(i)} {return {}}
    return [list $start [lindex [span c previous] 1]]
}

proc ::vhdl_index::parser::generate_parameter {state} {
    upvar 1 $state c
    set name [read_name c]
    set in [span c]
    expect c in
    set begin $c(i)
    set extent [generate_extent c {generate}]
    set fence $c(i)
    set c(grammarFence) $fence
    set c(grammarDomain) GENERATE
    set c(grammarNamePrefix) 0
    set c(grammarPrefixes) {}
    set c(i) $begin
    set status parsed
    set issue {}
    set diagnostics {}
    if {[catch {::vhdl_index::grammar::discrete_range c 0 {eof}} range options]} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX GENERATE}} {
            return -options $options $range
        }
        set status recognized-but-unsupported
        set diagnostics [list $range]
        if {$extent eq {} || [dict get $range code] ni
            {GENERATE_EXPECTED_RANGE_DIRECTION GENERATE_EXPECTED_DIMENSION_SEPARATOR}} {
            set status malformed
            set issue $range
        }
        set range [dict create kind opaque span $extent]
    } elseif {$c(i) != $fence} {
        set status malformed
        set issue [diagnostic c GENERATE_INVALID_DISCRETE_RANGE {}]
    }
    set c(i) $fence
    set nameSpan [lindex $name 1]
    set parameter [dict create kind generate_parameter name [lindex $name 0] name_span $nameSpan in_span $in \
        span [list [lindex $nameSpan 0] [lindex [span c previous] 1]] range $range status $status diagnostics $diagnostics]
    return [list $parameter $issue]
}

proc ::vhdl_index::parser::generate_choices {state} {
    upvar 1 $state c
    set choices {}
    set separators {}
    set issue {}
    while {1} {
        set form expression
        set first $c(i)
        set extent [generate_extent c {| =>}]
        if {$extent eq {}} {
            set issue [diagnostic c GENERATE_EXPECTED_CHOICE {}]
        } else {
            if {$c(i) == $first + 1 && [peek c -1] eq "others"} {set form others}
            lappend choices [dict create kind $form span $extent \
                status [expr {$form eq "others" ? "parsed" : "opaque"}]]
        }
        if {[peek c] eq "=>"} {break}
        lappend separators [take c]
    }
    return [list $choices $separators $issue]
}

proc ::vhdl_index::parser::generate_alternative {state depth owner form seenVar} {
    upvar 1 $state c $seenVar seen
    set keyword [take c]
    set opening [lindex $keyword 0]
    set label {}
    set colon {}
    set issue {}
    if {[peek c 1] eq ":"} {
        if {$c(edition) < 2008} {fail c EDITION_GENERATE_ALTERNATIVE_LABEL}
        if {[is_name [peek c] 0]} {
            set label [read_name c]
            set key [lindex $label 2]
            if {[dict exists $seen $key]} {
                set issue [diagnostic c DUPLICATE_ALTERNATIVE_LABEL [list span [lindex $label 1] related_span [dict get $seen $key]]]
            }
            if {$issue eq {}} {dict set seen $key [lindex $label 1]}
        } else {
            set issue [diagnostic c INVALID_ALTERNATIVE_LABEL {}]
            incr c(i)
        }
        set colon [take c]
    }
    set syntax [dict create form $form keyword_span $keyword label [lindex $label 0] \
        label_span [lindex $label 1] colon_span $colon]
    if {$form eq "when"} {
        lassign [generate_choices c] choices separators choiceIssue
        if {$issue eq {}} {set issue $choiceIssue}
        dict set syntax choices $choices
        dict set syntax separator_spans $separators
        dict set syntax arrow_span [take c]
    } else {
        if {$form ne "else"} {
            set condition [generate_extent c {generate}]
            if {$condition eq {} && $issue eq {}} {set issue [diagnostic c GENERATE_EXPECTED_CONDITION {}]}
            dict set syntax condition_span $condition
            dict set syntax condition_status opaque
        }
        set marker [span c]
        expect c generate
        dict set syntax generate_span $marker
    }
    dict set syntax header_span [list $opening [lindex [span c previous] 1]]
    scope c generate_alternative $label $depth generate [list $opening $owner] {} {} $syntax $issue
    return $syntax
}

proc ::vhdl_index::parser::generate_statement {state depth owner ownerKind label} {
    upvar 1 $state c
    if {$label eq {}} {fail c MISSING_GENERATE_LABEL}
    if {$ownerKind eq "entity"} {fail c GENERATE_OUT_OF_CONTEXT}
    set form [peek c]
    if {$form eq "case" && $c(edition) < 2008} {fail c EDITION_CASE_GENERATE}
    set depth [descend c $depth]
    set opening [lindex $label 1 0]
    set syntax [dict create form $form label [lindex $label 0] label_span [lindex $label 1] colon_span [span c previous]]
    if {$form eq "for"} {
        dict set syntax keyword_span [take c]
        lassign [generate_parameter c] parameter issue
        dict set syntax parameter $parameter
        dict set syntax generate_span [take c]
        dict set syntax header_span [list $opening [lindex [span c previous] 1]]
        scope c for_generate $label $depth generate [list $opening $owner] {} {} $syntax $issue
        return
    }
    set checkpoint [::vhdl_index::ownership::checkpoint c]
    set active [open_named_scope c generate $label]
    set seen {}
    set alternativeDepth [descend c $depth]
    if {$form eq "case"} {
        dict set syntax keyword_span [take c]
        set selector [generate_extent c {generate}]
        if {$selector eq {}} {fail c GENERATE_EXPECTED_SELECTOR}
        dict set syntax selector_span $selector
        dict set syntax selector_status opaque
        dict set syntax generate_span [take c]
        dict set syntax header_span [list $opening [lindex [span c previous] 1]]
        if {[peek c] ne "when"} {fail c GENERATE_EXPECTED_WHEN}
        while {[peek c] eq "when"} {
            generate_alternative c $alternativeDepth $opening when seen
        }
    } else {
        set first [generate_alternative c $alternativeDepth $opening if seen]
        dict set syntax keyword_span [dict get $first keyword_span]
        dict set syntax generate_span [dict get $first generate_span]
        dict set syntax header_span [list $opening [lindex [dict get $first header_span] 1]]
        while {[peek c] in {elsif else}} {
            if {$c(edition) < 2008} {fail c EDITION_GENERATE_ALTERNATIVE}
            set next [peek c]
            generate_alternative c $alternativeDepth $opening $next seen
            if {$next eq "else"} {break}
        }
    }
    set before [llength $c(diagnostics)]
    set tail [terminator c generate $label]
    close_named_scope c $active
    set region [list $opening [lindex $tail 1]]
    set kind ${form}_generate
    if {[llength $c(diagnostics)] != $before} {
        ::vhdl_index::ownership::rollback c $checkpoint $kind $region [lindex $c(diagnostics) end] $owner
        return
    }
    set syntax [dict merge $syntax [scope_closing c $tail {}]]
    # Sparse scope rows retain a two-point fence. The logical view exposes
    # no declarative inventory for the outer if/case envelope.
    set fence [lindex [dict get $syntax header_span] 1]
    ::vhdl_index::ownership::publish c [dict create id $opening parent_id $owner kind $kind \
        name_span [lindex $label 1] span $region declarative_span [list $fence $fence] entries {} \
        opaque {} gaps {} status parsed types {} type_status parsed syntax $syntax]
}

# The scope walker alone consumes declarations and nested typed statements.
# This function deals only with the boundary already reached by that walk.
proc ::vhdl_index::parser::generate_body_end {state kind name} {
    upvar 1 $state c
    set inner {}
    set innerName {}
    if {[peek c] eq "end" && [peek c 1] ne "generate"} {
        if {$c(edition) < 2008} {fail c EDITION_GENERATE_BODY_END}
        set label $name
        if {$kind eq "for_generate"} {set label {}}
        set inner [terminator c alternative $label 1 0 0 1]
        set innerName [dict get [scope_closing c $inner {}] end_name_span]
    }
    if {$kind eq "for_generate"} {
        set tail [terminator c generate $name]
    } else {
        if {[peek c] ni {elsif else when} && !([peek c] eq "end" && [peek c 1] eq "generate")} {
            fail c UNPROVEN_GENERATE_ALTERNATIVE_END
        }
        set tail $inner
    }
    return [list $tail $inner $innerName]
}
