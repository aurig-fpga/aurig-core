#!/usr/bin/tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Test comment parsing on test_entity.vhd

set script_anchor [file dirname [file normalize [info script]]]
set fixture_dir [file dirname $script_anchor]
set aurig_core_root [file dirname $fixture_dir]
lappend ::auto_path $aurig_core_root
package require aurig::core

set test_file [file join $fixture_dir test_entity.vhd]

puts "=== Testing comment parsing on $test_file ===\n"

set parse_dict [::aurig::core::analyze::vhdlscan -in $test_file -verbosity 0]

# Check if we have metadata
if {[dict exists $parse_dict metadata]} {
    puts "✓ Metadata found:"
    dict for {key val} [dict get $parse_dict metadata] {
        puts "  $key: $val"
    }
} else {
    puts "✗ No metadata found"
}

# Check entities and their comments
set entities [::aurig::core::analyze::q_entity_names $parse_dict]
puts "\n✓ Entities: $entities"

foreach ent $entities {
    puts "\nEntity: $ent"
    
    # Check for entity comment
    if {[dict exists $parse_dict entity $ent comment]} {
        puts "  Comment: [dict get $parse_dict entity $ent comment]"
    }
    
    # Check generics and their comments
    set generics [::aurig::core::analyze::q_entity_generics $parse_dict $ent]
    if {[llength $generics] > 0} {
        puts "  Generics:"
        foreach gen $generics {
            set name [lindex $gen 0]
            set type [lindex $gen 1]
            puts "    - $name : $type"
        }
    }
    
    # Check ports and their comments
    set ports [::aurig::core::analyze::q_entity_ports $parse_dict $ent]
    if {[llength $ports] > 0} {
        puts "  Ports:"
        foreach port $ports {
            set name [lindex $port 0]
            set mode [lindex $port 1]
            set type [lindex $port 2]
            puts "    - $name : $mode $type"
        }
    }
}

puts "\n=== Test complete ==="
