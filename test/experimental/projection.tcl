# Test-only common-subset projection for vhdlscan root record lists.
namespace eval ::comparison {
    variable keys {libraries uses entities architectures packages package_bodies}
    variable unit_keys {entity entities architecture architectures package packages package_body package_bodies}
}

proc ::comparison::experimental {result} {
    variable keys
    variable unit_keys
    set projected {}
    foreach key $keys {dict set projected $key {}}
    set source [dict get $result snapshot]
    set line 0
    foreach unit [dict get $result units] {
        foreach item [dict get $unit context] {
            set at [lindex [::vhdl_index::next_position $source [lindex [dict get $item span] 0] line] 0]
            foreach name [dict get $item names] {
                set parts {}
                foreach part [dict get $name components] {
                    lappend parts [::vhdl_index::slice $source $part]
                }
                if {[dict get $item kind] eq "library"} {
                    dict lappend projected libraries [dict create name [lindex $parts 0] line $at]
                } elseif {[dict get $item kind] eq "use"} {
                    set use [dict create lib [lindex $parts 0] selector [join [lrange $parts 2 end] .] line $at]
                    if {[llength $parts] != 2 || [string tolower [lindex $parts 1]] ne "all"} {
                        dict set use pkg [lindex $parts 1]
                    } else {
                        dict set use selector [lindex $parts 1]
                    }
                    dict lappend projected uses $use
                }
            }
        }
        set kind [dict get $unit kind]
        if {![dict exists $unit_keys $kind]} {continue}
        set lineNumber [lindex [::vhdl_index::next_position $source [lindex [dict get $unit span] 0] line] 0]
        set record [dict create name [dict get $unit name] line $lineNumber]
        if {$kind eq "architecture"} {dict set record entity [dict get $unit target]}
        dict lappend projected [dict get $unit_keys $kind] $record
    }
    return $projected
}

proc ::comparison::records {dict key} {
    set identities {}
    set lines {}
    foreach record [dict get $dict $key] {
        if {$key eq "uses"} {
            set pkg {}
            if {[dict exists $record pkg]} {set pkg [dict get $record pkg]}
            lappend identities [list [dict get $record lib] $pkg [dict get $record selector]]
        } elseif {$key eq "architectures"} {
            lappend identities [list [dict get $record name] [dict get $record entity]]
        } else {
            lappend identities [dict get $record name]
        }
        lappend lines [dict get $record line]
    }
    return [list $identities $lines]
}
