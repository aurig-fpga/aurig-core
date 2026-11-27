# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set fixture [file join $tests fixtures abstract-exponents.vhd.fixture]
set decoded [::aurig::core::util::read_vhdl_source $fixture]
set snapshot [::vhdl_index::snapshot abstract-literal-lexing $decoded]
foreach edition {1993 2002 2008} {
    set tape [::vhdl_index::lexer::lex $snapshot $edition [::vhdl_index::limits {}]]
    set diagnostics {}
    foreach issue [dict get $tape diagnostics] {
        lappend diagnostics [list [dict get $issue code] [::vhdl_index::slice $snapshot [dict get $issue span]]]
    }
    if {$diagnostics ne {{INVALID_NUMBER 23E-3} {INVALID_NUMBER 16#D#e-2}}} {
        error "Unrecognized integer exponent restriction ($edition): $diagnostics"
    }
    set kinds {}
    foreach idx [dict get $tape significant] {
        lappend kinds [lindex [::vhdl_index::lexer::token $tape $idx] 0]
    }
    if {$kinds ne {number invalid number number invalid number number eof}} {
        error "Unexpected numeric token accounting ($edition): $kinds"
    }
}
puts "PASS abstract literal exponent signs in three editions"
