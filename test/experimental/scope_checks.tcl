# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

proc check {label expected actual} {
    if {$expected ne $actual} {error [list $label expected $expected actual $actual]}
}
proc scope_input {source {edition 2008} {limits {}}} {
    set scratch $::env(AURIG_EXPERIMENTAL_SCRATCH)
    file mkdir $scratch
    set path [file join $scratch scope.vhd.fixture]
    set fp [open $path w]
    puts -nonewline $fp $source
    close $fp
    return [::vhdl_index::analyze_file $path $edition $limits]
}
proc surface {r span} {
    ::vhdl_index::slice [dict get $r snapshot] $span
}
proc scope_find {v kind prefix} {
    foreach row [::vhdl_index::query::owners $v] {
        if {[dict get $row kind] eq $kind && [string first $prefix [surface [dict get $v result] [dict get $row span]]] == 0} {
            return [dict get $row id]
        }
    }
    error [list owner_missing $kind $prefix]
}
proc scope_shape {v id} {
    dict get [::vhdl_index::regions::region $v $id] syntax
}
proc scope_rows {v id capability} {
    dict get [::vhdl_index::query::direct $v $id $capability] rows
}
proc scope_complete {v id capability} {
    dict get [::vhdl_index::regions::coverage $v $id $capability] completeness
}
proc scope_error {r} {
    dict get [lindex [dict get $r structural_diagnostics] 0] code
}
proc scope_integrity {r v} {
    set offset 0
    set text {}
    foreach segment [dict get $r ledger] {
        lassign $segment state first last
        check ledger $offset $first
        set offset $last
        append text [surface $r [list $first $last]]
    }
    check reconstruction [dict get $r snapshot text] $text
    foreach row [::vhdl_index::query::owners $v] {
        set parent [dict get $row parent_id]
        if {$parent eq {}} {
            check root_loss uncertain [dict get $row availability]
            continue
        }
        set outer [::vhdl_index::regions::region $v $parent]
        check parent_present 1 [dict exists $outer span]
        lassign [dict get $outer span] a b
        lassign [dict get $row span] x y
        check containment 1 [expr {$a <= $x && $x <= $y && $y <= $b}]
        if {[dict get $row availability] ne "proved"} {
            check withdrawn_syntax 0 [dict exists $row syntax]
        }
    }
}
