# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# This file can also be sourced by the private_queries workflow entry.
if {![llength [info commands ::vhdl_index::query::direct]]} {
    source [file join [file dirname [info script]] startup.tcl]
}
source [file join $tests scope_checks.tcl]

proc query_namespace_state {namespace} {
    set state {}
    foreach name [lsort [info vars ${namespace}::*]] {
        if {$name eq "::vhdl_index::sourceSerial"} {continue}
        if {[array exists $name]} {
            set values {}
            foreach key [lsort [array names $name]] {lappend values $key [set ${name}($key)]}
            lappend state $name $values
        } elseif {[info exists $name]} {
            lappend state $name [set $name]
        }
    }
    lappend state commands [lsort [info commands ${namespace}::*]]
    foreach child [lsort [namespace children $namespace]] {
        lappend state $child [query_namespace_state $child]
    }
    return $state
}

proc query_expect_error {script expected} {
    set code [catch {uplevel 1 $script} result options]
    check error_return 1 $code
    check error_code $expected [dict get $options -errorcode]
    return $result
}

proc query_qualification {} {
    set state [query_namespace_state ::vhdl_index]
    set result [scope_input {entity e is end;
        architecture a of e is
            component c generic (package p is new work.g generic map (1)); end component wrong;
        begin
            u: target;
            removed: block begin
                nested: if true generate
                    p: process (all) begin null; end process wrong;
                    assert true;
                end generate;
            end block wrong;
            b: block begin
                keep: process (all) begin null; end process;
                call_it(1);
                o <= '1';
                k: component c port map(open);
            end block;
        end;}]
    set view [::vhdl_index::regions::view $result]
    set a [scope_find $view architecture {architecture a}]
    set b [scope_find $view block b:]
    set source [dict get $result source_id]
    foreach capability {instantiations concurrent_procedure_calls map_associations} {
        check parent_evidence partial [scope_complete $view $a $capability]
    }
    set empty [::vhdl_index::query::direct $view $a concurrent_assertions]
    check verified_empty complete [dict get $empty completeness]
    check empty_rows {} [dict get $empty rows]
    foreach capability {process_headers sensitivity_lists} {
        set out [::vhdl_index::query::subtree $view $a $capability]
        check child_loss partial [dict get $out completeness]
        check surviving_child 1 [llength [dict get $out rows]]
        check child_owner $b [dict get [lindex [dict get $out rows] 0] owner_occurrence_id]
        set seen {}
        foreach proof [dict get $out evidence] {
            foreach key {evidence_id loss_id} {
                if {[dict exists $proof $key]} {
                    set id [dict get $proof $key]
                    check unique_proof 0 [dict exists $seen $id]
                    dict set seen $id 1
                }
            }
        }
    }
    set process [lindex [scope_rows $view $b process_headers] 0]
    set clause [lindex [scope_rows $view $b sensitivity_lists] 0]
    check process_link [dict get $process occurrence_id] [dict get $clause process_occurrence_id]
    set absent [::vhdl_index::regions::identity $view {region -1}]
    check absent_region absent [dict get [::vhdl_index::regions::region $view $absent] availability]
    check absent_subtree absent [dict get [::vhdl_index::query::subtree $view $absent instantiations] completeness]
    query_expect_error {::vhdl_index::query::subtree $view $a record_fields} {VHDL_INDEX SUBTREE}

    # Reuse the same path with different bytes and retain both snapshots.
    set second [::vhdl_index::regions::view [scope_input {entity newer is end;}]]
    check distinct_snapshot 1 [expr {$source ne [dict get $second source_id]}]
    check first_snapshot {entity e} [::vhdl_index::query::text $view $source {0 8}]
    query_expect_error {::vhdl_index::query::direct $second $a instantiations} {VHDL_INDEX REGION_ID}
    query_expect_error {::vhdl_index::query::subtree $second $a instantiations} {VHDL_INDEX REGION_ID}
    query_expect_error {::vhdl_index::regions::coverage $second $a instantiations} {VHDL_INDEX REGION_ID}
    query_expect_error {::vhdl_index::query::position $second $source 0} {VHDL_INDEX SNAPSHOT_ID}
    query_expect_error {::vhdl_index::query::text $second $source {0 1}} {VHDL_INDEX SNAPSHOT_ID}
    query_expect_error {::vhdl_index::query::text $view $source {one 1}} {VHDL_INDEX SPAN}
    query_expect_error {::vhdl_index::query::position $view $source one} {VHDL_INDEX OFFSET}
    unset result view second
    check no_retention $state [query_namespace_state ::vhdl_index]
}

proc query_emit {stream key value} {
    set row [list $key $value]
    puts $stream [string bytelength $row]
    puts $stream $row
}

proc query_transcript {manifestPath outputPath} {
    set manifest [open $manifestPath r]
    set out [open $outputPath w]
    fconfigure $out -translation lf -encoding utf-8
    set capabilities {unit_boundaries context entity_interfaces object_declarations type_declarations
        subprogram_specifications subprogram_bodies alias_declarations attribute_declarations file_objects
        group_templates group_declarations local_use_clauses map_associations component_declarations
        disconnect_specifications configuration_specifications configuration_blocks package_declarations
        package_instantiations package_interfaces block_interfaces generate_parameters instantiations
        concurrent_assertions concurrent_procedure_calls actual_parameter_associations process_headers
        sensitivity_lists concurrent_signal_assignments formal_parameters component_interfaces record_fields physical_units}
    set subtreeCaps [lsearch -all -inline -not -regexp $capabilities \
        {^(unit_boundaries|context|entity_interfaces|formal_parameters|component_interfaces|record_fields|physical_units|package_interfaces|block_interfaces)$}]
    set inputs 0
    set queries 0
    while {[gets $manifest line] >= 0} {
        lassign [split $line "\t"] edition path
        set result [::vhdl_index::analyze_file $path $edition]
        set view [::vhdl_index::regions::view $result]
        set source [dict get $view source_id]
        dict unset result timing_us
        query_emit $out [list $edition $path parse] $result
        query_emit $out units [::vhdl_index::query::units $view]
        query_emit $out owners [::vhdl_index::query::owners $view]
        set addresses [dict keys [dict get $view rows]]
        lappend addresses {region -1}
        foreach address $addresses {
            set id [::vhdl_index::regions::identity $view $address]
            check identity [linsert $address 0 $source] $id
            query_emit $out [list region $address] [::vhdl_index::regions::region $view $id]
            foreach capability $capabilities {
                set answer [::vhdl_index::query::direct $view $id $capability]
                set rows [dict get $answer rows]
                foreach row $rows {
                    check occurrence_snapshot $source [lindex [dict get $row occurrence_id] 0]
                    set owner [dict get $row owner_occurrence_id]
                    if {$owner ne {}} {
                        check owner_snapshot $source [lindex $owner 0]
                        check owner_exists 1 [dict exists $view rows [lrange $owner 1 end]]
                    }
                }
                check coverage [dict remove $answer rows] [::vhdl_index::regions::coverage $view $id $capability]
                query_emit $out [list direct $address $capability] $answer
                incr queries 2
                if {$capability in $subtreeCaps && [lindex $address 0] in {unit region gap recovery}} {
                    set nested [::vhdl_index::query::subtree $view $id $capability]
                    query_emit $out [list subtree $address $capability] $nested
                    incr queries
                }
            }
        }
        incr inputs
    }
    close $manifest
    close $out
    puts [list QUERY-TRANSCRIPT [info patchlevel] inputs $inputs queries $queries]
}

if {[lindex $argv 0] eq "--query-corpus"} {
    query_transcript [lindex $argv 1] [lindex $argv 2]
} else {
    query_qualification
    puts [list QUERY-QUALIFICATION-PASS [info patchlevel]]
}
