source [file join [file dirname [info script]] startup.tcl]
foreach name {grouped-interface} {
    set r [::vhdl_index::analyze_file [file join $workspace _tasks AURIG-004-A fixtures $name.vhd] 2008]
    set hasCoverage [dict exists $r capabilities entity_interfaces]
    puts [list $name expected_capability 1 actual_capability $hasCoverage]
    if {!$hasCoverage} {exit 1}
}
