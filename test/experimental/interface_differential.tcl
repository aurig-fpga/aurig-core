source [file join [file dirname [info script]] startup.tcl]
source [file join $tests interface_projection.tcl]
lassign $argv corpus output
set lines [open $corpus]
set out [open $output w]

proc row {out args} {
    puts $out [join $args "\t"]
}
proc encoded {value} {
    binary scan [encoding convertto utf-8 $value] H* hex
    return $hex
}
proc emit {out fixture arm index key record} {
    set mode {}
    if {[dict exists $record mode]} {set mode [string tolower [dict get $record mode]]}
    set init {}
    if {[dict exists $record init]} {set init [dict get $record init]}
    row $out $fixture $arm object $index $key [encoded [dict get $record name]] \
        $mode [encoded [dict get $record type]] [encoded $init]
}
while {[gets $lines fixture] >= 0} {
    if {[string match /* $fixture]} {
        set path $fixture
        set fixture [file tail $path]
    } else {
        set path [file join $core test parser fixtures $fixture]
    }
    set r [::vhdl_index::analyze_file $path 2008]
    set arm [dict get $r engine]
    set status opaque
    if {[dict exists $r capabilities entity_interfaces]} {
        set status [dict get $r capabilities entity_interfaces]
    } elseif {[dict get $r recovery] ne {}} {
        set status unrecognized
    }
    set codes {}
    if {[dict exists $r interface_diagnostics]} {
        foreach diagnostic [dict get $r interface_diagnostics] {lappend codes [dict get $diagnostic code]}
    }
    row $out $fixture $arm status $status [join $codes ,]
    set projection [::interface_comparison::project $r]
    set i 0
    set order {}
    foreach entity [dict get $r units] {
        if {[dict get $entity kind] ne "entity"} {continue}
        row $out $fixture $arm entity $i [encoded [dict get $entity name]]
        set offset [lindex [dict get $entity span] 0]
        dict set order $offset $i
        foreach key {generic port} {
            if {![dict exists $projection [list $offset $key]]} {continue}
            foreach record [dict get $projection [list $offset $key]] {emit $out $fixture $arm $i $key $record}
        }
        incr i
    }
    if {[dict exists $r entity_interfaces]} {
        foreach owner [dict get $r entity_interfaces] {
            set index [dict get $order [lindex [dict get $owner owner_span] 0]]
            foreach clause [dict get $owner clauses] {
                foreach item [dict get $clause items] {
                    set category [dict get $item category]
                    if {$category in {object unknown}} {continue}
                    foreach name [dict get $item names] {
                        row $out $fixture $arm category $index [dict get $clause kind] $category \
                            [encoded [::vhdl_index::slice [dict get $r snapshot] $name]]
                    }
                }
            }
        }
    }
    if {$arm eq "tcl-span-index/0"} {continue}
    foreach lint {0 1} {
        set mode "legacy-$lint"
        if {[catch {::aurig::core::analyze::vhdlscan -in $path -lint $lint} parsed]} {
            row $out $fixture $mode status errored [encoded $parsed]
            continue
        }
        row $out $fixture $mode status returned {}
        set i 0
        foreach entity [dict get $parsed entities] {
            row $out $fixture $mode entity $i [encoded [dict get $entity name]]
            foreach {key collection} {generic generics port ports} {
                foreach record [dict get $entity $collection] {emit $out $fixture $mode $i $key $record}
            }
            incr i
        }
    }
}
close $lines
close $out
