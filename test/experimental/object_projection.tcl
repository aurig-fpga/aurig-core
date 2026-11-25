# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::object_comparison {}

# A test visitor flattens grouped name spans into selected legacy fields.
proc ::object_comparison::visit {result consumer} {
    set source [dict get $result snapshot]
    foreach scope [dict get $result object_declarations] {
        foreach entry [dict get $scope entries] {
            for {set index 0} {$index < [lindex $entry 1]} {incr index} {
                set item [::vhdl_index::object::record $result $scope $entry $index]
                if {[dict get $item status] ne "parsed"} {continue}
                set kind [dict get $item kind]
                set type [::vhdl_index::slice $source [dict get $item subtype_span]]
                set init {}
                if {[dict get $item init_span] ne {}} {
                    set init [::vhdl_index::slice $source [dict get $item init_span]]
                }
                foreach span [dict get $item names] {
                    set name [::vhdl_index::slice $source $span]
                    {*}$consumer $scope [list $kind $name $type $init] $span
                }
            }
        }
    }
}
