namespace eval ::interface_comparison {}

# Ordinals preserve entity identity even when source names repeat. This is a
# test-only projection of object interfaces, separate from root inventory.
proc ::interface_comparison::project {result} {
    set projected {}
    if {![dict exists $result entity_interfaces]} {return $projected}
    set snapshot [dict get $result snapshot]
    foreach owner [dict get $result entity_interfaces] {
        set ordinal [lindex [dict get $owner owner_span] 0]
        foreach clause [dict get $owner clauses] {
            set key [dict get $clause kind]
            if {$key ni {generic port}} {continue}
            foreach item [dict get $clause items] {
                if {[dict get $item category] ne "object" || [dict get $item status] ne "parsed"} {continue}
                set record [dict create type [::vhdl_index::slice $snapshot [dict get $item subtype_span]]]
                if {$key eq "port"} {dict set record mode [dict get $item effective_mode]}
                if {[dict get $item default_span] ne {}} {
                    dict set record init [::vhdl_index::slice $snapshot [dict get $item default_span]]
                }
                foreach span [dict get $item names] {
                    dict set record name [::vhdl_index::slice $snapshot $span]
                    dict lappend projected [list $ordinal $key] $record
                }
            }
        }
    }
    return $projected
}

proc ::interface_comparison::count_list {record totalsVar} {
    upvar 1 $totalsVar totals
    dict for {key value} $record {
        if {$value eq {}} {continue}
        if {[string match *_span $key] || $key eq "span"} {
            dict incr totals interface_spans
        } elseif {[string match *_spans $key] || $key eq "names"} {
            dict incr totals interface_spans [llength $value]
        }
    }
    foreach item [dict get $record items] {
        dict incr totals interface_items
        dict incr totals interface_names [llength [dict get $item names]]
        dict for {key value} $item {
            if {$value eq {}} {continue}
            if {[string match *_span $key] || $key eq "span"} {
                dict incr totals interface_spans
            } elseif {[string match *_spans $key] || $key eq "names"} {
                dict incr totals interface_spans [llength $value]
            }
        }
        if {[dict exists $item parameters]} {count_list [dict get $item parameters] totals}
    }
}

proc ::interface_comparison::counts {result} {
    set totals {interface_owners 0 interface_clauses 0 interface_items 0 interface_names 0 interface_spans 0}
    if {![dict exists $result entity_interfaces]} {return $totals}
    set owners [dict get $result entity_interfaces]
    dict set totals interface_owners [llength $owners]
    foreach owner $owners {
        dict incr totals interface_spans 2
        foreach clause [dict get $owner clauses] {
            dict incr totals interface_clauses
            count_list $clause totals
        }
    }
    return $totals
}
