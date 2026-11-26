# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set scratch $::env(AURIG_EXPERIMENTAL_SCRATCH)
file mkdir $scratch
proc check {label actual expected} {
    if {$actual ne $expected} {error [list $label expected $expected observed $actual]}
}
proc analyze {text edition} {
    set path [file join $::scratch selected.vhd.fixture]
    set fp [open $path w]
    puts $fp $text
    close $fp
    return [::vhdl_index::analyze_file $path $edition]
}
foreach edition {1993 2002 2008} {
    foreach {suffix code} [list {"+"} {} {"AnD"} {} {"bad"} INVALID_OPERATOR {"?="} EDITION_OPERATOR "\\a name\\" {} {} EXPECTED_NAME] {
        if {$suffix eq {"?="} && $edition == 2008} {set code {}}
        set head "use work.p.$suffix;"
        set r [analyze "$head entity ok is end;" $edition]
        set unit [lindex [dict get $r units] 0]
        check unit [dict get $unit name] ok
        set item [lindex [dict get $unit context] 0]
        check context_span [::vhdl_index::slice [dict get $r snapshot] [dict get $item span]] $head
        check root_capability [dict get $r capabilities context] [expr {$code eq {} ? "parsed" : "malformed"}]
        if {$code ne {}} {
            set expected [expr {$code eq "EDITION_OPERATOR" ? $code : "CONTEXT_$code"}]
            check root_code [dict get [lindex [dict get $item diagnostics] 0] code] $expected
        }
        set r [analyze "package p is $head constant k : integer; end;" $edition]
        set scope [lindex [dict get $r object_declarations] 0]
        check preserved_constant [llength [dict get $scope entries]] 1
        set item [lindex [dict get $scope declarations] 0]
        if {$code ne {}} {
            set expected [expr {$code eq "EDITION_OPERATOR" ? $code : "LOCAL_USE_$code"}]
            check local_code [dict get [lindex [dict get $item diagnostics] 0] code] $expected
        } else {
            check local_status [dict get $item status] parsed
        }
    }
}
set r [analyze {use work.p."bad", work.p."+", work.\a name\.all; entity ok is end;} 2008]
set clause [lindex [dict get [lindex [dict get $r units] 0] context] 0]
check multiple_uses [llength [dict get $clause names]] 3
check diagnostic_count [llength [dict get $clause diagnostics]] 1
set r [analyze {context c is use work.p."bad"; library work; end context; entity ok is end;} 2008]
check context_declaration [llength [dict get [lindex [dict get $r units] 0] context_items]] 2
check context_capability [dict get $r capabilities context] malformed
set r [analyze {use work.p. entity ok is end;} 2008]
check uncertain_recovery [dict get $r capabilities unit_boundaries] unrecognized
puts "Selected names passed on Tcl [info patchlevel]"
