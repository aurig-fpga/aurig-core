# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Interface sites are fenced before running the shared formal grammar. Maps
# use a separate, opaque association envelope.
proc ::vhdl_index::parser::formal_site {state} {
    upvar 1 $state c
    set first $c(i)
    incr c(i)
    if {[peek c] ne "("} {fail c EXPECTED_INTERFACE_GROUP}
    set c(grammarFence) [llength $c(significant)]
    set c(grammarDomain) INTERFACE
    if {[catch {::vhdl_index::grammar::group c 1} cause options]} {
        if {[dict get $options -errorcode] ne {VHDL_INDEX INTERFACE}} {
            return -options $options $cause
        }
        return -code error -errorcode {VHDL_INDEX STRUCTURE} $cause
    }
    accept c {;}
    return [list $first $c(i) 1 {}]
}

proc ::vhdl_index::parser::map_aspect {state form} {
    upvar 1 $state c
    set keyword [take c]
    set connector [span c]
    expect c map
    set open [span c]
    consume_group c
    set close [span c previous]
    return [dict create kind $form span [list [lindex $keyword 0] [lindex $close 1]] \
        keyword_span $keyword map_span $connector open_span $open close_span $close \
        association_span [list [lindex $open 1] [lindex $close 0]] association_status opaque]
}

proc ::vhdl_index::parser::package_header {state name head} {
    upvar 1 $state c
    set shape [dict create header_span $head name [lindex $name 0] interfaces {} generic_map {}]
    if {[peek c] ne "generic"} {return $shape}
    if {$c(edition) < 2008} {fail c EDITION_PACKAGE_GENERIC}
    if {[peek c 1] eq "map"} {fail c EXPECTED_GENERIC_CLAUSE}
    set site [formal_site c]
    set owner [dict create name_span [lindex $name 1] span $head]
    dict set shape interfaces [dict get [::vhdl_index::interface::index_owner c $owner [list $site] scopeLexicalAt] clauses]
    if {[peek c] eq "generic"} {
        set map [map_aspect c generic]
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
        consume_group c
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
            set map [map_aspect c $form]
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
    set marker [boundary c {{;} end begin block process generate elsif =>}]
    if {$marker eq ";"} {
        incr c(i)
    } elseif {$marker eq "end" && $ownerKind ni {block generate}} {
        # Preserve the preexisting end-boundary diagnostic on other bodies.
        lappend c(diagnostics) [diagnostic c MISSING_SEMICOLON {}]
    } else {
        fail c UNPROVEN_CONCURRENT_BOUNDARY [list found $marker]
    }
}
