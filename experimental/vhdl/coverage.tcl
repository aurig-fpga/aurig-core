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

proc ::vhdl_index::declaration_capability {kind} {
    switch -- $kind {
        package - package_body {return package_declarations}
        package_instantiation {return package_instantiations}
        alias {return alias_declarations}
        component {return component_declarations}
        file_object {return file_objects}
        local_use {return local_use_clauses}
        attribute - attribute_declaration - attribute_specification {return attribute_declarations}
        group_template {return group_templates}
        group {return group_declarations}
        disconnect {return disconnect_specifications}
        configuration_specification {return configuration_specifications}
    }
    return {}
}

proc ::vhdl_index::declaration_capabilities {row} {
    if {[dict exists $row candidate_capabilities]} {
        return [dict get $row candidate_capabilities]
    }
    set capability [declaration_capability [dict get $row kind]]
    if {$capability eq {}} {return {}}
    return [list $capability]
}

# Association rows stay on their enclosing syntax. Assemble a private view of
# maps without duplicating their contents in the retained index.
proc ::vhdl_index::maps_at {result address payload} {
    lassign $address role at
    set maps {}
    if {$role eq "region" && [dict exists $result instantiations $at]} {
        foreach row [dict get $result instantiations $at] {lappend maps {*}[dict values [dict get $row maps]]}
    }
    return $maps
}

proc ::vhdl_index::coverage {snapshot tape structure} {
    set length [dict get $snapshot length]
    set ledger {}
    set offset 0
    set opaque {}
    set context parsed
    foreach unit [dict get $structure units] {
        foreach item [dict get $unit context] {
            set state parsed
            if {[dict exists $item status]} {
                set state [dict get $item status]
                set context [::vhdl_index::grammar::combine $context $state]
            }
            cover_through ledger offset $state [dict get $item span]
        }
        if {[dict get $unit status] eq "malformed"} {
            cover_through ledger offset malformed [dict get $unit span]
        } else {
            cover_through ledger offset parsed [dict get $unit header_span]
            foreach item [dict get $unit context_items] {
                set state parsed
                if {[dict exists $item status]} {
                    set state [dict get $item status]
                    set context [::vhdl_index::grammar::combine $context $state]
                }
                cover_through ledger offset $state [dict get $item span]
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
    set additional {alias_declarations attribute_declarations component_declarations file_objects
        group_templates group_declarations disconnect_specifications local_use_clauses
        configuration_specifications configuration_blocks package_declarations package_instantiations package_interfaces block_interfaces generate_parameters
        instantiations map_associations}
    foreach capability $additional {dict set result capabilities $capability parsed}
    # Publish known gaps even when no declaration row was eligible for the scope.
    foreach gap [dict get $structure coverage_gaps] {
        foreach capability [dict get $gap capabilities] {
            dict set result capabilities $capability [::vhdl_index::grammar::combine \
                [dict get $result capabilities $capability] [dict get $gap status]]
        }
    }
    dict for {owner rows} [dict get $structure instantiations] {
        foreach map [maps_at $structure [list region $owner] {}] {
            dict set result capabilities map_associations [::vhdl_index::grammar::combine \
                [dict get $result capabilities map_associations] [dict get $map association_validation]]
        }
    }
    foreach scope [dict get $structure object_declarations] {
        if {[dict exists $scope syntax interfaces]} {
            set capability [dict get $scope kind]_interfaces
            foreach clause [dict get $scope syntax interfaces] {
                dict set result capabilities $capability [::vhdl_index::grammar::combine \
                    [dict get $result capabilities $capability] [dict get $clause status]]
            }
        }
        if {[dict exists $scope syntax parameter]} {
            dict set result capabilities generate_parameters [::vhdl_index::grammar::combine \
                [dict get $result capabilities generate_parameters] [dict get $scope syntax parameter status]]
        }
        if {![dict exists $scope declarations]} {continue}
        foreach row [dict get $scope declarations] {
            foreach capability [declaration_capabilities $row] {
                dict set result capabilities $capability [::vhdl_index::grammar::combine \
                    [dict get $result capabilities $capability] [dict get $row status]]
            }
        }
    }
    foreach lost [dict get $structure withdrawn_scopes] {
        foreach capability [dict get $lost capabilities] {
            dict set result capabilities $capability unrecognized
        }
    }
    return $result
}
