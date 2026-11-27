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

# Maps retain their caller-specific fields. This sparse index groups the
# shared map records by syntactic owner and source order.
proc ::vhdl_index::concurrent_at {result address capability} {
    set key [list [lindex $address 1] $capability]
    if {[dict exists $result concurrent_statements $key]} {
        return [dict get $result concurrent_statements $key]
    }
    return {}
}

proc ::vhdl_index::maps_at {result address} {
    if {[dict exists $result maps $address]} {return [dict get $result maps $address]}
    return {}
}

proc ::vhdl_index::interface_maps {clauses} {
    set maps {}
    foreach clause $clauses {
        if {[dict get $clause kind] ne "generic"} {continue}
        set items [dict get $clause items]
        if {$items eq {}} {lappend maps {*}[indeterminate_maps $clause]}
        foreach item $items {
            if {[dict exists $item generic_map]} {
                lappend maps [dict get $item generic_map]
            } elseif {[dict get $item category] in {unknown package}} {
                lappend maps {*}[indeterminate_maps $item]
            }
        }
    }
    return $maps
}

proc ::vhdl_index::collect_maps {units scopes interfaces instances} {
    set found {}
    foreach unit $units {
        if {[dict exists $unit syntax generic_map] && [dict get $unit syntax generic_map] ne {}} {
            dict lappend found [list unit [lindex [dict get $unit span] 0]] [dict get $unit syntax generic_map]
        }
    }
    foreach interface $interfaces {
        set address [list region [lindex [dict get $interface owner_span] 0]]
        foreach map [interface_maps [dict get $interface clauses]] {dict lappend found $address $map}
    }
    foreach scope $scopes {
        set address [list region [dict get $scope id]]
        set maps {}
        if {[dict exists $scope syntax]} {
            set shape [dict get $scope syntax]
            if {[dict exists $shape interfaces]} {lappend maps {*}[interface_maps [dict get $shape interfaces]]}
            if {[dict exists $shape maps]} {lappend maps {*}[dict get $shape maps]}
            if {[dict exists $shape generic_map] && [dict get $shape generic_map] ne {}} {
                lappend maps [dict get $shape generic_map]
            }
        }
        if {[dict exists $scope declarations]} {
            foreach declaration [dict get $scope declarations] {
                switch -- [dict get $declaration kind] {
                    component {lappend maps {*}[interface_maps [dict get $declaration clauses]]}
                    package_instantiation {
                        if {[dict get $declaration generic_map] ne {}} {
                            lappend maps [dict get $declaration generic_map]
                        }
                    }
                    configuration_specification {
                        foreach form {generic port} {
                            if {[dict exists $declaration binding ${form}_map]} {
                                lappend maps [dict get $declaration binding ${form}_map]
                            }
                        }
                        lappend maps {*}[indeterminate_maps $declaration]
                    }
                }
            }
        }
        if {[dict exists $scope subprograms]} {
            foreach spec [dict get $scope subprograms] {
                if {[dict exists $spec generic_parameters]} {
                    lappend maps {*}[interface_maps [list [dict merge {kind generic} [dict get $spec generic_parameters]]]]
                }
                if {[dict exists $spec generic_map]} {lappend maps [dict get $spec generic_map]}
                lappend maps {*}[indeterminate_maps $spec]
            }
        }
        if {$maps ne {}} {dict lappend found $address {*}$maps}
    }
    dict for {owner rows} $instances {
        foreach row $rows {
            foreach map [dict values [dict get $row maps]] {
                dict lappend found [list region $owner] \
                    [dict merge $map [dict create instantiation_start [lindex [dict get $row span] 0]]]
            }
        }
    }
    dict for {address maps} $found {
        set ordered {}
        foreach map $maps {lappend ordered [list [lindex [dict get $map span] 0] $map]}
        set sorted {}
        foreach pair [lsort -integer -index 0 $ordered] {lappend sorted [lindex $pair 1]}
        dict set found $address $sorted
    }
    return $found
}

# An established but broken caller may have lost an otherwise applicable map.
proc ::vhdl_index::indeterminate_maps {record} {
    set status [dict get $record status]
    if {$status ni {malformed unrecognized}} {return {}}
    return [list [dict create span [dict get $record span] association_validation $status \
        association_diagnostics [dict get $record diagnostics] associations {}]]
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
    foreach capability [concat $additional [::vhdl_index::ownership::concurrent_profile root] [::vhdl_index::ownership::sequential_profile root]] {
        dict set result capabilities $capability parsed
    }
    # Publish known gaps even when no declaration row was eligible for the scope.
    foreach gap [dict get $structure coverage_gaps] {
        foreach capability [dict get $gap capabilities] {
            dict set result capabilities $capability [::vhdl_index::grammar::combine \
                [dict get $result capabilities $capability] [dict get $gap status]]
        }
    }
    dict for {address maps} [dict get $structure maps] {
        foreach map $maps {
            dict set result capabilities map_associations [::vhdl_index::grammar::combine \
                [dict get $result capabilities map_associations] [dict get $map association_validation]]
        }
    }
    set scopes [dict get $structure object_declarations]
    if {[dict exists $structure sequential_regions]} {
        lappend scopes {*}[dict get $structure sequential_regions]
    }
    foreach scope $scopes {
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
        if {[dict exists $scope sequential]} {
            dict for {capability rows} [dict get $scope sequential] {
                foreach row $rows {
                    if {[dict get $row status] eq "parsed"} {continue}
                    dict set result capabilities $capability [::vhdl_index::grammar::combine \
                        [dict get $result capabilities $capability] [dict get $row status]]
                    if {$capability eq "sequential_procedure_calls"} {
                        set actuals sequential_actual_parameter_associations
                        dict set result capabilities $actuals [::vhdl_index::grammar::combine \
                            [dict get $result capabilities $actuals] [dict get $row status]]
                    }
                }
            }
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
