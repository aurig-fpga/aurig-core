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
