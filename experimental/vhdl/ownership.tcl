# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::vhdl_index::ownership {}

proc ::vhdl_index::ownership::unproven_scope {domain region cause} {
    return [dict create code ${domain}_UNPROVEN_SCOPE severity error phase structural span $region \
        related_span [dict get $cause span] cause [dict get $cause code]]
}

proc ::vhdl_index::ownership::concurrent_profile {kind} {
    if {$kind ni {root architecture entity block generate}} {return {}}
    set capabilities {concurrent_assertions concurrent_procedure_calls actual_parameter_associations process_headers sensitivity_lists}
    if {$kind ne "entity"} {lappend capabilities concurrent_signal_assignments}
    return $capabilities
}

namespace eval ::vhdl_index::ownership {
    variable sequentialCapabilities {
        sequential_assertions report_statements null_statements wait_statements control_flow_envelopes
    }
}

proc ::vhdl_index::ownership::sequential_profile {kind} {
    variable sequentialCapabilities
    if {$kind in {root process function procedure}} {return $sequentialCapabilities}
    return {}
}

proc ::vhdl_index::ownership::profile {kind} {
    return [concat [declaration_profile $kind] [sequential_profile $kind]]
}

# The direct profile sets the minimum affected coverage. Descendant claims
# and region gaps contribute their own capabilities independently.
proc ::vhdl_index::ownership::declaration_profile {kind} {
    switch -- $kind {
        root {
            return [concat [concurrent_profile root] {object_declarations type_declarations subprogram_specifications subprogram_bodies
                alias_declarations attribute_declarations file_objects component_declarations entity_interfaces
                group_templates group_declarations disconnect_specifications local_use_clauses
                configuration_specifications configuration_blocks package_declarations package_instantiations package_interfaces block_interfaces generate_parameters
                instantiations map_associations}]
        }
        if_generate - case_generate {return {}}
        for_generate {return [linsert [declaration_profile generate] end generate_parameters]}
        generate_alternative {return [declaration_profile generate]}
        component {return {component_declarations}}
        protected {return {subprogram_specifications attribute_declarations local_use_clauses map_associations}}
        configuration {return {attribute_declarations group_declarations local_use_clauses configuration_blocks map_associations}}
    }
    set result {object_declarations type_declarations subprogram_specifications subprogram_bodies
        alias_declarations attribute_declarations file_objects group_templates group_declarations local_use_clauses map_associations}
    if {$kind in {architecture package block generate}} {lappend result component_declarations}
    if {$kind in {architecture entity package block generate}} {lappend result disconnect_specifications}
    if {$kind in {architecture block generate}} {
        lappend result configuration_specifications instantiations
    }
    if {$kind in {architecture entity package package_body process function procedure protected_body block generate}} {
        lappend result package_declarations package_instantiations
    }
    if {$kind eq "package"} {lappend result package_interfaces}
    if {$kind eq "block"} {lappend result block_interfaces}
    if {$kind eq "entity"} {lappend result entity_interfaces}
    return [concat $result [concurrent_profile $kind]]
}

proc ::vhdl_index::ownership::gap {state kind region status capabilities owner {diagnostics {}} {forms {}}} {
    upvar 1 $state c
    set row [dict create kind $kind span $region status $status capabilities $capabilities owner_id $owner]
    if {$diagnostics ne {}} {dict set row diagnostics $diagnostics}
    if {$forms ne {}} {dict set row forms $forms}
    lappend c(coverageGaps) $row
}

proc ::vhdl_index::ownership::trim_suffix {state key length} {
    upvar 1 $state c
    if {[llength $c($key)] > $length} {
        set c($key) [lrange $c($key) 0 [expr {$length - 1}]]
    }
}

proc ::vhdl_index::ownership::withdrawal {kind region cause parent} {
    return [dict create scope_kind $kind span $region capabilities [profile $kind] diagnostic $cause parent_id $parent]
}

# Checkpoints are lengths of append-only lists. The walker keeps its
# own cursor, grammar fence, timing and diagnostic stream.
proc ::vhdl_index::ownership::checkpoint {state} {
    upvar 1 $state c
    return [list [llength $c(declarationScopes)] [llength $c(coverageGaps)] \
        [llength $c(withdrawnScopes)] [llength $c(objectDiagnostics)] \
        [llength $c(typeDiagnostics)] [llength $c(emptyRegions)] [llength $c(instantiations)] [llength $c(concurrentStatements)]]
}

proc ::vhdl_index::ownership::publish {state record} {
    upvar 1 $state c
    lappend c(declarationScopes) $record
}

proc ::vhdl_index::ownership::empty {state owner span} {
    upvar 1 $state c
    lappend c(emptyRegions) $owner $span
}

proc ::vhdl_index::ownership::withdraw_component {state span cause owner mapLoss} {
    upvar 1 $state c
    lappend c(withdrawnScopes) [withdrawal component $span $cause $owner]
    if {$mapLoss} {
        # Component maps belong to the enclosing declarative owner.
        gap c component_interface_loss $span unrecognized {map_associations} $owner [list $cause]
    }
}

proc ::vhdl_index::ownership::rollback {state checkpoint kind region cause parent {declarations {}}} {
    upvar 1 $state c
    set started [clock microseconds]
    lassign $checkpoint firstScope firstGap firstWithdrawal
    set lost [withdrawal $kind $region $cause $parent]
    set mask {}
    foreach capability [dict get $lost capabilities] {dict set mask $capability 1}
    set contributors [lrange $c(coverageGaps) $firstGap end]
    set lostChildren {}
    foreach child [lrange $c(withdrawnScopes) $firstWithdrawal end] {
        if {[dict exists $child contributors]} {
            lappend contributors {*}[dict get $child contributors]
            dict unset child contributors
        }
        if {[dict get $child scope_kind] ne "component"} {
            dict set lostChildren [lindex [dict get $child span] 0] 1
        }
        dict set child kind [dict get $child scope_kind]
        dict set child status unrecognized
        lappend contributors $child
    }
    foreach child [lrange $c(declarationScopes) $firstScope end] {
        # A lost scope contributes its fence and mask without its declaration
        # payload. Unrecognized placeholders already have a loss record.
        if {[dict exists $lostChildren [dict get $child id]]} {continue}
        set childKind [dict get $child kind]
        set childMask [profile $childKind]
        lappend contributors [dict create kind withdrawn_region span [dict get $child span] \
            status unrecognized capabilities $childMask scope_kind $childKind \
            parent_id [dict get $child parent_id]]
        if {[dict exists $child declarations]} {lappend declarations {*}[dict get $child declarations]}
    }
    foreach declaration $declarations {
        foreach capability [::vhdl_index::declaration_capabilities $declaration] {
            dict set mask $capability 1
        }
        if {[dict exists $declaration candidate_forms]} {
            lappend contributors [dict create kind declaration_candidates span [dict get $declaration span] \
                status [dict get $declaration status] capabilities [dict get $declaration candidate_capabilities] \
                forms [dict get $declaration candidate_forms] owner_id [dict get $declaration owner_id] \
                diagnostics [dict get $declaration diagnostics]]
        }
    }
    foreach contributor $contributors {
        foreach capability [dict get $contributor capabilities] {dict set mask $capability 1}
    }
    dict set lost capabilities [dict keys $mask]
    if {$contributors ne {}} {
        dict set lost contributors [lsort -integer -index {3 0} $contributors]
    }
    foreach key {declarationScopes coverageGaps withdrawnScopes objectDiagnostics typeDiagnostics emptyRegions instantiations concurrentStatements} length $checkpoint {
        trim_suffix c $key $length
    }
    lappend c(withdrawnScopes) $lost
    incr c(withdrawalTime) [expr {[clock microseconds] - $started}]
}
