# Root ledger rows are {state start end}. The lexical tape independently
# partitions all source, including trivia inside a root opaque span.
proc ::vhdl_index::cover_through {ledgerVar offsetVar state extent} {
    upvar 1 $ledgerVar ledger $offsetVar offset
    lassign $extent start end
    if {$start < $offset || $end < $start} {error "Overlapping coverage claim: $extent"}
    if {$offset < $start} {lappend ledger [list trivia $offset $start]}
    if {$start < $end} {lappend ledger [list $state $start $end]}
    set offset $end
}

proc ::vhdl_index::coverage {snapshot tape structure} {
    set length [dict get $snapshot length]
    set ledger {}
    set offset 0
    set opaque {}
    foreach unit [dict get $structure units] {
        foreach item [dict get $unit context] {
            cover_through ledger offset parsed [dict get $item span]
        }
        if {[dict get $unit status] eq "malformed"} {
            cover_through ledger offset malformed [dict get $unit span]
        } else {
            cover_through ledger offset parsed [dict get $unit header_span]
            foreach item [dict get $unit context_items] {
                cover_through ledger offset parsed [dict get $item span]
            }
            set region [dict get $unit opaque]
            if {$region ne {}} {
                set status opaque
                if {[dict get $unit status] eq "recognized-but-unsupported"} {
                    set status recognized-but-unsupported
                }
                cover_through ledger offset $status $region
            }
            cover_through ledger offset parsed [dict get $unit terminator_span]
        }
        if {[dict get $unit opaque] ne {}} {lappend opaque [dict get $unit opaque]}
    }
    foreach item [dict get $structure unowned_context] {
        cover_through ledger offset malformed [dict get $item span]
    }
    if {[dict get $structure recovery] ne {}} {
        cover_through ledger offset unrecognized [dict get $structure recovery]
    }
    cover_through ledger offset trivia [list $length $length]

    set lexical parsed
    foreach diagnostic [dict get $tape diagnostics] {
        set code [dict get $diagnostic code]
        if {$code in {TOKEN_LIMIT UNSUPPORTED_DIRECTIVE}} {
            if {$lexical eq "parsed"} {set lexical recognized-but-unsupported}
        } else {
            set lexical malformed
        }
    }
    set structural parsed
    set context parsed
    if {[dict get $structure recovery] ne {}} {
        set structural unrecognized
        set context unrecognized
    } elseif {[dict get $structure structural_diagnostics] ne {}} {
        set structural malformed
        if {[dict get $structure unowned_context] ne {}} {set context malformed}
    }
    set result [dict create ledger $ledger opaque_regions $opaque \
        capabilities [dict create source parsed accounting parsed lexical $lexical \
            unit_boundaries $structural context $context entity_interfaces [dict get $structure interface_status] \
            object_declarations [dict get $structure object_status] \
            subprogram_specifications [dict get $structure subprogram_status] \
            subprogram_bodies [dict get $structure body_status] \
            type_declarations [dict get $structure type_status] declarations opaque concurrent opaque \
            sequential opaque expressions opaque]]
    set additional {alias_declarations attribute_declarations}
    foreach capability $additional {dict set result capabilities $capability parsed}
    foreach scope [dict get $structure object_declarations] {
        if {[dict get $scope gaps] ne {} && [dict get $scope status] in {unrecognized recognized-but-unsupported}} {
            foreach capability $additional {
                dict set result capabilities $capability [::vhdl_index::grammar::combine \
                    [dict get $result capabilities $capability] [dict get $scope status]]
            }
        }
        if {![dict exists $scope declarations]} {continue}
        foreach row [dict get $scope declarations] {
            set capability [expr {[dict get $row kind] eq "alias" ? "alias_declarations" : "attribute_declarations"}]
            dict set result capabilities $capability [::vhdl_index::grammar::combine \
                [dict get $result capabilities $capability] [dict get $row status]]
        }
    }
    foreach lost [dict get $structure withdrawn_scopes] {
        foreach capability [dict get $lost capabilities] {
            dict set result capabilities $capability unrecognized
        }
    }
    return $result
}
