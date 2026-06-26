# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Test script for extended INI/YAML conversion support
# Tests: board section, sim config, include_dirs_global

package require Tcl 8.5

# Load the library
set scriptDir [file dirname [file normalize [info script]]]
set fixtureDir [file dirname $scriptDir]
set aurig_core_root [file dirname $fixtureDir]
lappend ::auto_path $aurig_core_root
package require aurig::core

# Converter output is scratch nobody validates against a golden -- it is only
# read back and printed for human review. Write it to a per-process temp dir so
# a suite run never dirties the tracked tree (TEST-HYGIENE-CONVERTED-CHURN), and
# remove the dir on exit.
proc scratchTempBase {} {
    foreach var {TMPDIR TEMP TMP} {
        if {[info exists ::env($var)] && $::env($var) ne ""} {
            return $::env($var)
        }
    }
    return [expr {$::tcl_platform(platform) eq "windows" ? "." : "/tmp"}]
}
set scratchDir [file join [scratchTempBase] "aurig_conv_[pid]"]
file mkdir $scratchDir

puts "=========================================="
puts "Testing Extended INI/YAML Conversion"
puts "=========================================="

# Test 1: INI -> YAML conversion
puts "\n\[1\] Testing INI to YAML conversion..."
set iniFile [file join $fixtureDir test_aca_updated.ini]
set yamlOut [file join $scratchDir test_aca_updated_converted.yaml]

if {[catch {
    ::aurig::core::util::ini2yaml $iniFile $yamlOut
    puts "  ✓ Converted $iniFile -> $yamlOut"
} err]} {
    puts "  ✗ ERROR: $err"
    puts $::errorInfo
}

# Test 2: YAML -> INI conversion
puts "\n\[2\] Testing YAML to INI conversion..."
set yamlFile [file join $fixtureDir test_aca_updated.yaml]
set iniOut [file join $scratchDir test_aca_updated_converted.ini]

if {[catch {
    ::aurig::core::util::yaml2ini $yamlFile $iniOut
    puts "  ✓ Converted $yamlFile -> $iniOut"
} err]} {
    puts "  ✗ ERROR: $err"
    puts $::errorInfo
}

# Test 3: Validate round-trip preservation
puts "\n\[3\] Validating feature preservation..."

proc checkSection {iniDict section keys} {
    set result {}
    if {[dict exists $iniDict $section]} {
        set sec [dict get $iniDict $section]
        foreach k $keys {
            if {[dict exists $sec $k]} {
                lappend result "$k: [dict get $sec $k]"
            } else {
                lappend result "$k: MISSING"
            }
        }
    } else {
        lappend result "Section [$section] NOT FOUND"
    }
    return $result
}

if {[catch {
    # Read converted INI
    set convertedIni [::aurig::core::util::readIni $iniOut]
    
    puts "\n  Checking \[board\] section:"
    foreach line [checkSection $convertedIni board {xdc_files sdc_files}] {
        puts "    $line"
    }
    
    puts "\n  Checking \[sim\] section:"
    foreach line [checkSection $convertedIni sim {top_tb tb_lib run_time}] {
        puts "    $line"
    }
    
    puts "\n  Checking \[includes\] section:"
    foreach line [checkSection $convertedIni includes {global}] {
        puts "    $line"
    }
    
    # Read converted YAML
    set convertedYaml [::aurig::core::util::readYaml $yamlOut]
    
    puts "\n  Checking YAML board section:"
    if {[dict exists $convertedYaml board]} {
        set board [dict get $convertedYaml board]
        if {[dict exists $board xdc_files]} {
            puts "    xdc_files: [dict get $board xdc_files]"
        }
        if {[dict exists $board sdc_files]} {
            puts "    sdc_files: [dict get $board sdc_files]"
        }
    } else {
        puts "    board section: MISSING"
    }
    
    puts "\n  Checking YAML sim section:"
    if {[dict exists $convertedYaml sim]} {
        set sim [dict get $convertedYaml sim]
        foreach k {top_tb tb_lib run_time} {
            if {[dict exists $sim $k]} {
                puts "    $k: [dict get $sim $k]"
            }
        }
    } else {
        puts "    sim section: MISSING"
    }
    
    puts "\n  Checking YAML include_dirs_global:"
    if {[dict exists $convertedYaml include_dirs_global]} {
        puts "    include_dirs_global: [dict get $convertedYaml include_dirs_global]"
    } else {
        puts "    include_dirs_global: MISSING"
    }
    
} err]} {
    puts "  ✗ ERROR during validation: $err"
    puts $::errorInfo
}

puts "\n=========================================="
puts "Test Complete!"
puts "=========================================="
puts "\nGenerated (scratch) files:"
puts "  - $yamlOut"
puts "  - $iniOut"

# Scratch output served its purpose (read back and printed above); drop it so
# nothing lingers outside the repo either.
file delete -force $scratchDir
