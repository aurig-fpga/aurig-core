# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $tests object_projection.tcl]
lassign $argv corpus target
set output [open $target w]
set manifest [open $corpus]

proc hex {value} {
    binary scan [encoding convertto utf-8 $value] H* text
    return $text
}
proc row {args} {
    puts $::output [join [list $::fixture $::arm {*}$args] "\t"]
}
proc get {record key} {
    if {![dict exists $record $key]} {return {}}
    return [dict get $record $key]
}
proc experimental {scope row span} {
    lassign $row kind name type init
    lassign [::vhdl_index::position [dict get $::result snapshot] [lindex $span 0]] line col
    row object [dict get $scope id] $kind [hex $name] [hex $type] [hex $init] $line $col
}
proc legacy_scope {kind name parent decls} {
    set id [incr ::serial]
    row scope $id $parent $kind [hex $name] available
    foreach decl $decls {
        set class [dict get $decl kind]
        set name [dict get $decl name]
        if {$class in {function procedure}} {
            legacy_scope $class $name $id [get $decl body_declarations]
        } elseif {$class in {constant signal variable}} {
            set data $decl
            if {[dict exists $decl args]} {set data [lindex [dict get $decl args] 0]}
            row object $id $class [hex $name] [hex [get $data type]] [hex [get $data init]] [get $decl line] {}
        }
    }
    return $id
}

while {[gets $manifest line] >= 0} {
    lassign [split $line "\t"] fixture path
    set arm D
    set result [::vhdl_index::analyze_file $path 2008]
    set source [dict get $result snapshot]
    set codes {}
    foreach issue [dict get $result object_diagnostics] {lappend codes [dict get $issue code]}
    row status [dict get $result capabilities object_declarations] [hex $codes]
    set indexed {}
    foreach scope [dict get $result object_declarations] {
        set extent [dict get $scope name_span]
        set name {}
        if {$extent ne {}} {set name [::vhdl_index::slice $source $extent]}
        set id [dict get $scope id]
        dict set indexed $id 1
        row scope $id [dict get $scope parent_id] [dict get $scope kind] [hex $name] [dict get $scope status]
    }
    foreach unit [dict get $result units] {
        set id [lindex [dict get $unit span] 0]
        set kind [dict get $unit kind]
        if {$kind ni {package package_body architecture entity} || [dict exists $indexed $id]} {continue}
        row scope $id {} $kind [hex [dict get $unit name]] [dict get $unit status]
    }
    ::object_comparison::visit $result experimental

    foreach lint {0 1} {
        set arm "legacy-$lint"
        set serial 0
        if {[catch {::aurig::core::analyze::vhdlscan -in $path -lint $lint} prior]} {
            row status unavailable [hex $prior]
            continue
        }
        row status returned {}
        foreach unit [dict get $prior architectures] {
            set parent [legacy_scope architecture [dict get $unit name] {} [get $unit declarations]]
            foreach process [get $unit processes] {
                legacy_scope process [get $process label] $parent [get $process declarations]
            }
        }
        foreach unit [dict get $prior packages] {
            legacy_scope package [dict get $unit name] {} [get $unit declarations]
        }
        foreach unit [get $prior package_bodies] {
            legacy_scope package_body [dict get $unit name] {} [concat [get $unit functions] [get $unit procedures]]
        }
    }
}
close $manifest
close $output
