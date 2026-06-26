# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# File        : core.tcl
# Purpose     : Entry point for the aurig::core package
# Description : Loads the util foundation and the analysis stack, then
#               provides aurig::core. This is the dependency closure that
#               makes ::aurig::core::analyze::vhdlscan usable standalone, without
#               relying on the aurig umbrella's source ordering. The lint
#               engine and other consumers `package require aurig::core`
#               instead of assuming init.tcl sourced analyze/* first.
#=============================================================================

# Suppress tclIndex errors from ActiveTcl auto-loading. These are cosmetic
# errors from missing/broken system tclIndex files. Applied here (not only in
# init.tcl) so a standalone `package require aurig::core` is equally quiet.
if {![info exists ::aurig_core_auto_load_patched]} {
    set ::aurig_core_auto_load_patched 1

    if {[info commands ::_original_unknown] eq ""} {
        rename ::unknown ::_original_unknown
        proc ::unknown {args} {
            if {[catch {::_original_unknown {*}$args} result options]} {
                # Silently ignore tclIndex open failures
                if {[string match "*tclIndex*" $result]} {
                    return -code error "invalid command name \"[lindex $args 0]\""
                }
                return -options $options $result
            }
            return $result
        }
    }
}

# Single source of truth for the toolkit version. The umbrella (init.tcl)
# reads this same variable for `package provide aurig` and for artifact
# emitters' tool_version stamp.
namespace eval ::aurig::core {
    variable version 0.1.0
}

# Base directory where this file is located
set dir [file dirname [info script]]

# Util foundation: the analysis stack depends on ::aurig::core::util::* and
# ::aurig::core::util::re::*. These five modules are that closure. create_ini_file
# (the VHDL/Quartus/ISE -> ini conversion utility) is NOT here: it has no
# lint/doc consumer, so it is a rump leaf loaded by init.tcl, not core.
source [file join $dir util common.tcl]
source [file join $dir util vhdl_re.tcl]
source [file join $dir util ini_yaml.tcl]
source [file join $dir util project_files.tcl]

# Parser stack: the shared analysis closure lint and doc both depend on.
# The project-analysis leaf tools (scan_project + its dependencies / project /
# power_rename / vhdlscan_reports siblings) are NOT loaded here -- they depend
# on this core for their parser/util needs, not the other way round, so loading
# them lives in the rump entry (init.tcl), keeping core carve-out-ready.
source [file join $dir analyze schema.tcl]
source [file join $dir analyze queries.tcl]
source [file join $dir analyze parser_utils.tcl]
source [file join $dir analyze vhdlscan.tcl]

# Project-manifest schema infrastructure (::aurig::core::schema): load + normalize
# + validate the canonical AURIG manifest, and the parser-class consumer
# (scan_project). Depends on the util + parser stacks sourced above
# (_expand_glob_pattern for file_sets globbing, vhdlscan/q_entity_names for top
# name->file resolution). Project-mode loading requires tcllib yaml + json at
# RUN time -- not at source time -- so this source line stays dependency-free.
source [file join $dir schema manifest.tcl]

package provide aurig::core $::aurig::core::version
