source [file join [file dirname [info script]] startup.tcl]
lassign $argv index edition output
set channel [open $index]
set rows [split [string trimright [read $channel] "\n"] "\n"]
close $channel
set out [open $output w]
fconfigure $out -encoding utf-8 -translation lf

# Tab separators are safe after escaping embedded formatting in unusual names.
proc row {out args} {
    set values {}
    foreach value $args {
        lappend values [string map [list "\\" "\\\\" "\t" "\\t" "\n" "\\n"] $value]
    }
    puts $out [join $values "\t"]
}

foreach fixture $rows {
    set path [file join $core test parser fixtures $fixture]
    set result [::vhdl_index::analyze_file $path $edition]
    set projected [::comparison::experimental $result]
    set extended {}
    foreach unit [dict get $result units] {
        set kind [dict get $unit kind]
        if {$kind ni {entity architecture package package_body}} {
            lappend extended [list $kind [dict get $unit name]]
        }
        foreach item [dict get $unit context] {
            if {[dict get $item kind] eq "context"} {
                lappend extended [list context_reference \
                    [::vhdl_index::slice [dict get $result snapshot] [dict get $item span]]]
            }
        }
    }
    set diagnoses {}
    foreach key {lexical_diagnostics structural_diagnostics} {
        foreach detail [dict get $result $key] {lappend diagnoses [dict get $detail code]}
    }
    foreach lint {0 1} {
        set legacyFailed [catch {::aurig::core::analyze::vhdlscan -in $path -lint $lint} legacy options]
        row $out $fixture $lint analysis $legacyFailed $diagnoses \
            [expr {$legacyFailed ? $legacy : {}}]
        row $out $fixture $lint new_capabilities {} $extended {}
        foreach key $::comparison::keys {
            lassign [::comparison::records $projected $key] names lines
            if {$legacyFailed} {
                row $out $fixture $lint $key {} $names unavailable
            } else {
                lassign [::comparison::records $legacy $key] prior priorLines
                row $out $fixture $lint $key $prior $names {}
                if {$prior eq $names && $names ne {}} {
                    row $out $fixture $lint ${key}_lines $priorLines $lines {}
                }
            }
        }
    }
}
close $out
puts [list runtime [info patchlevel] package [package provide aurig::core] loader \
    [package ifneeded aurig::core 0.2.0] reader $::vhdl_index::readerPath fixtures [llength $rows]]
foreach path $loadedSources {puts [list loaded $path]}
