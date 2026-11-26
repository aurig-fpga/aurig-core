# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::regions {}

# A navigation view is requested explicitly. Source and syntax payloads are
# shared with the result. Local addresses stay compact until returned.
proc ::vhdl_index::regions::view {result} {
    set rows {}
    set losses {}
    set gaps {}
    foreach loss [dict get $result withdrawn_scopes] {
        set kind [dict get $loss scope_kind]
        set parent [dict get $loss parent_id]
        set span [dict get $loss span]
        set at [lindex $span 0]
        set role [expr {$kind eq "component" ? "component" : "region"}]
        if {$kind eq "root"} {
            set role recovery
            set availability uncertain
        } else {
            set availability withdrawn
            dict set losses [list $role $at] 1
        }
        set sourceParent {}
        if {$parent ne {}} {set sourceParent [list region $parent]}
        dict set rows [list $role $at] [list $kind $span {} $sourceParent $availability $loss]
    }
    foreach unit [dict get $result units] {
        set kind [dict get $unit kind]
        set span [dict get $unit span]
        set at [lindex $span 0]
        set key [list unit $at]
        dict set rows $key [list $kind $span {} {} proved $unit]
        if {[dict exists $result empty_regions $at]} {
            dict set rows [list region $at] [list $kind $span [dict get $result empty_regions $at] $key proved {}]
        } elseif {[dict exists $losses [list region $at]]} {
            set lost [dict get $rows [list region $at]]
            lset lost 3 $key
            dict set rows [list region $at] $lost
        }
    }
    foreach record [dict get $result object_declarations] {
        set at [dict get $record id]
        set key [list region $at]
        if {[dict exists $losses $key]} {continue}
        set parent [dict get $record parent_id]
        if {$parent eq {}} {
            set parent [list unit $at]
        } else {
            set parent [list region $parent]
        }
        dict set rows $key [list [dict get $record kind] [dict get $record span]             [dict get $record declarative_span] $parent proved $record]
        if {[dict exists $record subprograms]} {
            foreach spec [dict get $record subprograms] {
                set span [dict get $spec specification_span]
                dict set rows [list specification [lindex $span 0]] [list [dict get $spec category] $span $span $key proved $spec]
            }
        }
        if {[dict exists $record declarations]} {
            foreach row [dict get $record declarations] {
                if {[dict get $row kind] ne "component"} {continue}
                set span [dict get $row span]
                set member [list component [lindex $span 0]]
                if {![dict exists $losses $member]} {
                    dict set rows $member [list component $span $span $key proved $row]
                }
            }
        }
        foreach row [dict get $record types] {
            if {![dict exists $row fields] && ![dict exists $row primary_unit]} {continue}
            set span [dict get $row span]
            dict set rows [list type_members [lindex $span 0]]                 [list [dict get $row kind] $span $span $key proved $row]
        }
    }
    foreach row [dict get $result entity_interfaces] {
        set extent [dict get $row owner_span]
        set anchor [lindex $extent 0]
        dict set rows [list interface $anchor] [list entity $extent $extent [list unit $anchor] proved $row]
    }
    foreach gap [dict get $result coverage_gaps] {
        set kind [dict get $gap kind]
        set span [dict get $gap span]
        set owner [dict get $gap owner_id]
        if {$owner eq {}} {set parent {}} else {set parent [list region $owner]}
        set address [list gap [lindex $span 0]]
        # Several gap records can describe the same start with distinct roles.
        if {[dict exists $rows $address]} {
            set address [list gap [lindex $span 0] $kind]
        }
        set availability [expr {[dict get $gap status] eq "unrecognized" ? "uncertain" : "unsupported"}]
        dict set rows $address [list $kind $span {} $parent $availability $gap]
        if {$parent ne {}} {dict lappend gaps $parent $address}
    }
    return [dict create result $result source_id [dict get $result source_id] rows $rows gaps $gaps]
}

proc ::vhdl_index::regions::identity {view address} {
    if {$address eq {}} {return {}}
    return [linsert $address 0 [dict get $view source_id]]
}

proc ::vhdl_index::regions::address {view id} {
    if {[llength $id] ni {3 4} || [lindex $id 0] ne [dict get $view source_id]} {
        return -code error -errorcode {VHDL_INDEX REGION_ID} "Expected occurrence identity from this snapshot"
    }
    return [lrange $id 1 end]
}

proc ::vhdl_index::regions::region {view id} {
    set key [address $view $id]
    if {![dict exists $view rows $key]} {return [dict create id $id availability absent]}
    lassign [dict get $view rows $key] kind span inventory parent availability payload
    return [dict create id $id kind $kind span $span inventory_span $inventory         parent_id [identity $view $parent] availability $availability]
}

# Applicable profile for direct queries. A scope that fences an opaque child
# never inherits that child's legal declaration kinds for direct queries.
proc ::vhdl_index::regions::applicable {role kind capability} {
    switch -- $role {
        unit {return [expr {$capability in {unit_boundaries context} || ($kind eq "entity" && $capability eq "entity_interfaces")}]}
        interface {return [expr {$capability eq "entity_interfaces"}]}
        specification {return [expr {$capability in {subprogram_specifications formal_parameters}}]}
        component {return [expr {$capability eq "component_interfaces"}]}
        type_members {
            return [expr {($kind eq "record" && $capability eq "record_fields") ||
                ($kind eq "physical" && $capability eq "physical_units")}]
        }
        region {
            return [expr {$capability ni {entity_interfaces} &&
                $capability in [::vhdl_index::parser::region_capabilities $kind]}]
        }
    }
    return 0
}

proc ::vhdl_index::regions::evidence {view address capability row} {
    return [dict create owner_id [identity $view $address] kind declaration span [dict get $row span]         status [dict get $row status] capabilities [list $capability] diagnostics [dict get $row diagnostics]]
}

# Inspect only the requested family's retained records. Compact object runs
# have already passed the entire profile and require no expansion here.
proc ::vhdl_index::regions::coverage {view id capability} {
    set key [address $view $id]
    if {![dict exists $view rows $key]} {
        return [dict create availability absent completeness absent validation unrecognized evidence {}]
    }
    lassign [dict get $view rows $key] kind span inventory parent availability payload
    set role [lindex $key 0]
    set validation parsed
    set proofs {}
    if {$availability ne "proved"} {
        if {[dict exists $payload capabilities] && $capability in [dict get $payload capabilities]} {
            set completeness unavailable
            lappend proofs [dict merge $payload [dict create loss_id $id evidence_role $role]]
            set validation [expr {$availability eq "unsupported" ? "recognized-but-unsupported" : "unrecognized"}]
        } else {
            set completeness not_applicable
        }
    } elseif {![applicable $role $kind $capability]} {
        set completeness not_applicable
        set validation opaque
    } else {
        set completeness complete
        if {[dict exists $view gaps $key]} {
            foreach address [dict get $view gaps $key] {
                lassign [dict get $view rows $address] gapKind gapSpan _ _ boundary gap
                if {$capability ni [dict get $gap capabilities] ||
                    ($boundary eq "unsupported" && $gapKind in {package block generate configuration_block configuration_block_item}
                     && $capability ne "configuration_blocks")} {continue}
                set validation [::vhdl_index::grammar::combine $validation [dict get $gap status]]
                lappend proofs [dict merge $gap [dict create owner_id $id evidence_id [identity $view $address]]]
            }
        }
        foreach row [coverage_rows $view $role $capability $payload] {
            if {[dict get $row status] eq "parsed"} {continue}
            set validation [::vhdl_index::grammar::combine $validation [dict get $row status]]
            lappend proofs [evidence $view $key $capability $row]
        }
        if {$validation ne "parsed"} {set completeness partial}
    }
    return [dict create availability $availability completeness $completeness validation $validation evidence $proofs]
}

proc ::vhdl_index::regions::coverage_rows {view role capability payload} {
    if {$payload eq {}} {return {}}
    set rows {}
    switch -- $role {
        unit {
            switch -- $capability {
                unit_boundaries {
                    if {[dict get $payload status] ne "parsed"} {
                        set issues {}
                        set span [dict get $payload span]
                        foreach issue [dict get $view result structural_diagnostics] {
                            if {[lindex [dict get $issue span] 0] >= [lindex $span 0] &&
                                [lindex [dict get $issue span] 1] <= [lindex $span 1]} {lappend issues $issue}
                        }
                        lappend rows [dict merge $payload [dict create diagnostics $issues]]
                    }
                }
                context {
                    foreach clause [concat [dict get $payload context] [dict get $payload context_items]] {
                        if {[dict exists $clause status]} {lappend rows $clause}
                    }
                }
                entity_interfaces {
                    set at [lindex [dict get $payload span] 0]
                    if {[dict exists $view rows [list interface $at]]} {
                        set interface [lindex [dict get $view rows [list interface $at]] 5]
                        lappend rows [dict merge $interface [dict create span [dict get $interface owner_span]]]
                    } elseif {[dict exists $view rows [list region $at]] &&
                        [lindex [dict get $view rows [list region $at]] 4] eq "withdrawn"} {
                        set loss [lindex [dict get $view rows [list region $at]] 5]
                        lappend rows [dict create span [dict get $loss span] status unrecognized diagnostics [list [dict get $loss diagnostic]]]
                    }
                }
            }
        }
        interface {
            lappend rows [dict merge $payload [dict create span [dict get $payload owner_span]]]
        }
        specification - component - type_members {lappend rows $payload}
        region {
            switch -- $capability {
                object_declarations {
                    foreach entry [dict get $payload entries] {
                        if {[llength $entry] > 2} {lappend rows [lindex $entry 2]}
                    }
                }
                type_declarations {set rows [dict get $payload types]}
                subprogram_specifications - subprogram_bodies {
                    if {![dict exists $payload subprograms]} {return {}}
                    foreach spec [dict get $payload subprograms] {
                        if {$capability eq "subprogram_specifications"} {
                            lappend rows $spec
                        } elseif {[dict get $spec category] eq "body" && [dict exists $spec body_status]} {
                            lappend rows [dict replace $spec status [dict get $spec body_status] diagnostics [dict get $spec body_diagnostics]]
                        }
                    }
                }
                default {
                    if {![dict exists $payload declarations]} {return {}}
                    foreach row [dict get $payload declarations] {
                        if {$capability in [::vhdl_index::declaration_capabilities $row]} {lappend rows $row}
                    }
                }
            }
        }
    }
    return $rows
}
