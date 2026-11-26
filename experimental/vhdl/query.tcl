# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::query {}

proc ::vhdl_index::query::units {view} {
    set rows {}
    foreach item [dict get $view result units] {
        set at [lindex [dict get $item span] 0]
        lappend rows [dict merge $item [dict create occurrence_id [::vhdl_index::regions::identity $view [list unit $at]]]]
    }
    return $rows
}

proc ::vhdl_index::query::owners {view} {
    set addresses [lsort -integer -index 1 [dict keys [dict get $view rows]]]
    set regions {}
    foreach address $addresses {
        if {[lindex $address 0] ne "unit"} {
            lappend regions [::vhdl_index::regions::region $view [::vhdl_index::regions::identity $view $address]]
        }
    }
    return $regions
}

proc ::vhdl_index::query::items {view address capability payload} {
    if {$payload eq {}} {return {}}
    set role [lindex $address 0]
    switch -- $role {
        unit {
            switch -- $capability {
                context {return [concat [dict get $payload context] [dict get $payload context_items]]}
                unit_boundaries {return [list $payload]}
                entity_interfaces {
                    set key [list interface [lindex $address 1]]
                    if {[dict exists $view rows $key]} {
                        return [dict get [lindex [dict get $view rows $key] 5] clauses]
                    }
                }
            }
            return {}
        }
        interface - component {return [dict get $payload clauses]}
        specification {
            if {$capability eq "subprogram_specifications"} {return [list $payload]}
            if {[dict exists $payload parameters]} {return [dict get $payload parameters items]}
            return {}
        }
        type_members {
            if {$capability eq "record_fields" && [dict exists $payload fields]} {
                return [dict get $payload fields]
            }
            if {$capability eq "physical_units" && [dict exists $payload primary_unit]} {
                return [linsert [dict get $payload secondary_units] 0 [dict get $payload primary_unit]]
            }
            return {}
        }
    }
    if {$capability eq "object_declarations"} {
        set rows {}
        foreach entry [dict get $payload entries] {
            for {set index 0} {$index < [lindex $entry 1]} {incr index} {
                lappend rows [::vhdl_index::object::record [dict get $view result] $payload $entry $index]
            }
        }
        return $rows
    }
    if {$capability eq "subprogram_bodies"} {
        set rows {}
        foreach row [::vhdl_index::regions::coverage_rows $view $role $capability $payload] {
            if {[dict exists $row body_scope_id]} {lappend rows $row}
        }
        return $rows
    }
    return [::vhdl_index::regions::coverage_rows $view $role $capability $payload]
}

proc ::vhdl_index::query::direct {view id capability} {
    set address [::vhdl_index::regions::address $view $id]
    set result [::vhdl_index::regions::coverage $view $id $capability]
    set materialized {}
    if {[dict get $result completeness] in {complete partial}} {
        set role [lindex $address 0]
        set payload [lindex [dict get $view rows $address] 5]
        set occurrenceRole declaration
        switch -- $role {
            specification {set occurrenceRole [expr {$capability eq "formal_parameters" ? "parameter" : "specification"}]}
            type_members {set occurrenceRole [expr {$capability eq "record_fields" ? "record_field" : "physical_unit"}]}
            interface - component {set occurrenceRole interface_clause}
            unit {
                switch -- $capability {
                    context {set occurrenceRole context_item}
                    unit_boundaries {set occurrenceRole unit}
                    entity_interfaces {set occurrenceRole interface_clause}
                }
            }
            region {
                switch -- $capability {
                    subprogram_specifications {set occurrenceRole specification}
                    subprogram_bodies {set occurrenceRole region}
                }
            }
        }
        set owner $id
        if {$role eq "specification" && $occurrenceRole eq "specification"} {
            set owner [::vhdl_index::regions::identity $view [lindex [dict get $view rows $address] 3]]
        } elseif {$occurrenceRole eq "unit"} {
            set owner {}
        }
        foreach row [items $view $address $capability $payload] {
            if {$occurrenceRole eq "specification"} {dict set row span [dict get $row specification_span]}
            set at [lindex [dict get $row span] 0]
            set identity [::vhdl_index::regions::identity $view [list $occurrenceRole $at]]
            lappend materialized [dict merge $row [dict create occurrence_id $identity owner_occurrence_id $owner]]
        }
    }
    dict set result rows $materialized
    return $result
}

# Subtree inventory accepts syntax declaration capabilities. Member records
# use direct queries on their dedicated owners, and are never counted twice.
proc ::vhdl_index::query::subtree {view id capability} {
    set root [::vhdl_index::regions::address $view $id]
    if {[lindex $root 0] ni {region unit gap recovery} || $capability ni [::vhdl_index::ownership::profile root] ||
        $capability eq "entity_interfaces"} {
        return -code error -errorcode {VHDL_INDEX SUBTREE} "Expected a declarative owner and declaration capability"
    }
    if {![dict exists $view rows $root]} {return [direct $view $id $capability]}
    set children {}
    dict for {address entry} [dict get $view rows] {
        set parent [lindex $entry 3]
        if {$parent ne {}} {dict lappend children $parent $address}
    }
    set pending [list $root]
    set proofs {}
    set rows {}
    set validation parsed
    set proved 0
    set incomplete 0
    for {set i 0} {$i < [llength $pending]} {incr i} {
        set address [lindex $pending $i]
        if {[dict exists $children $address]} {lappend pending {*}[dict get $children $address]}
        if {[lindex $address 0] ni {region unit gap recovery}} {continue}
        set outcome [direct $view [::vhdl_index::regions::identity $view $address] $capability]
        set status [dict get $outcome completeness]
        if {$status in {not_applicable absent}} {continue}
        if {$status in {complete partial}} {set proved 1}
        if {$status ne "complete"} {set incomplete 1}
        set validation [::vhdl_index::grammar::combine $validation [dict get $outcome validation]]
        lappend proofs {*}[dict get $outcome evidence]
        foreach row [dict get $outcome rows] {lappend rows [list [lindex [dict get $row span] 0] $row]}
    }
    if {$proved} {
        set status [expr {$incomplete ? "partial" : "complete"}]
    } else {
        set status [expr {$incomplete ? "unavailable" : "not_applicable"}]
        if {!$incomplete} {set validation opaque}
    }
    set ordered {}
    foreach pair [lsort -integer -index 0 $rows] {lappend ordered [lindex $pair 1]}
    return [dict create availability [lindex [dict get $view rows $root] 4] completeness $status         validation $validation evidence $proofs rows $ordered]
}

proc ::vhdl_index::query::snapshot {view sourceId} {
    if {$sourceId ne [dict get $view source_id]} {
        return -code error -errorcode {VHDL_INDEX SNAPSHOT_ID} "Expected span coordinates from this snapshot"
    }
    return [dict get $view result snapshot]
}

proc ::vhdl_index::query::text {view sourceId span} {
    if {[llength $span] != 2 || ![string is integer -strict [lindex $span 0]] ||
        ![string is integer -strict [lindex $span 1]]} {
        return -code error -errorcode {VHDL_INDEX SPAN} "Expected two normalized offsets"
    }
    return [::vhdl_index::slice [snapshot $view $sourceId] $span]
}

proc ::vhdl_index::query::position {view sourceId offset} {
    if {![string is integer -strict $offset]} {
        return -code error -errorcode {VHDL_INDEX OFFSET} "Expected a normalized offset"
    }
    return [::vhdl_index::position [snapshot $view $sourceId] $offset]
}
