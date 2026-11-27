# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set fixture [file join $tests fixtures relative-external.vhd.fixture]
set decoded [::aurig::core::util::read_vhdl_source $fixture]
set snapshot [::vhdl_index::snapshot relative-external-lexing $decoded]
set inheritedTags {}
foreach delimiter {? @ << >> ?= ?/= ?< ?<= ?> ?>= ??} {
    lappend inheritedTags [dict get $::vhdl_index::lexer::symbols $delimiter]
}
if {$inheritedTags ne {151 152 153 154 155 156 157 158 159 160 161}} {
    error "Changed inherited VHDL-2008 token tape tags: $inheritedTags"
}
foreach edition {1993 2002 2008} {
    set tape [::vhdl_index::lexer::lex $snapshot $edition [::vhdl_index::limits {}]]
    set carets {}
    set reconstructed {}
    foreach idx [lrange [dict get $tape significant] 0 end-1] {
        lassign [::vhdl_index::lexer::token $tape $idx] kind start end
        if {[::vhdl_index::slice $snapshot [list $start $end]] eq "^"} {
            lappend carets $kind
        }
    }
    for {set idx 0} {$idx < [llength [dict get $tape kinds]] - 1} {incr idx} {
        lassign [::vhdl_index::lexer::token $tape $idx] kind start end
        append reconstructed [::vhdl_index::slice $snapshot [list $start $end]]
    }
    set expected [expr {$edition == 2008 ? "^ ^" : "invalid invalid"}]
    if {$carets ne $expected || $reconstructed ne [dict get $snapshot text] ||
        (($edition == 2008) != ([dict get $tape diagnostics] eq {}))} {
        error "Unexpected external-path lexical result ($edition): $carets [dict get $tape diagnostics]"
    }
}
puts "PASS relative external-path token and lossless accounting"
