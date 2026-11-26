# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set assertions 0
set failures 0
proc check {label expected actual} {
    incr ::assertions
    if {$expected ne $actual} {
        incr ::failures
        puts [list FAIL $label expected $expected actual $actual]
    }
}
proc analyze {label text} {
    file mkdir $::env(AURIG_EXPERIMENTAL_SCRATCH)
    set path [file join $::env(AURIG_EXPERIMENTAL_SCRATCH) $label.vhd]
    set channel [open $path w]
    puts $channel $text
    close $channel
    return [::vhdl_index::analyze_file $path 2008]
}
proc objects {result} {
    set rows {}
    set source [dict get $result snapshot]
    foreach scope [dict get $result object_declarations] {
        foreach entry [dict get $scope entries] {
            for {set index 0} {$index < [lindex $entry 1]} {incr index} {
                set item [::vhdl_index::object::record $result $scope $entry $index]
                lappend rows [list [::vhdl_index::slice $source [dict get $item span]] [dict get $item status]]
            }
        }
    }
    return $rows
}
proc codes {result} {
    set rows {}
    foreach issue [dict get $result object_diagnostics] {
        lappend rows [dict get $issue code]
    }
    return $rows
}

foreach {label declaration} {
    type {type t is (a, b);}
    subtype {subtype t is integer;}
    file {file f : text;}
    alias {alias a : integer is c;}
    attribute {attribute a : integer;}
    subprogram {procedure p;}
    function {pure function "+" (l, r : integer) return integer;}
    body {procedure p is variable inner : bit; begin null; end procedure;}
    object {signal middle, other : bit;}
} {
    set r [analyze "before-$label" "entity e is\n    constant c : integer := 0\n    $declaration\n    signal s : bit;\nend;"]
    puts [list $label [dict get $r capabilities object_declarations] [codes $r] [objects $r]]
    check "$label status" malformed [dict get $r capabilities object_declarations]
    check "$label diagnostic" OBJECT_MISSING_SEMICOLON [lindex [codes $r] 0]
    check "$label no swallowed text" {{constant c : integer := 0} malformed} [lindex [objects $r] 0]
    check "$label following sibling" 1 [expr {[list {signal s : bit;} parsed] in [objects $r]}]
}
foreach {label declaration} {
    type {type t is (a, b)}
    subtype {subtype t is integer}
    subprogram {procedure p}
} {
    set r [analyze "opaque-$label" "entity e is $declaration signal hidden : bit; signal kept : bit; end;"]
    check "$label opaque status" unrecognized [dict get $r capabilities object_declarations]
    check "$label opaque diagnostic" OBJECT_OPAQUE_BOUNDARY [lindex [codes $r] 0]
    check "$label opaque retention" {{{signal kept : bit;} parsed}} [objects $r]
}
set r [analyze opaque-file {entity e is file f : text signal hidden : bit; signal kept : bit; end;}]
check indexed-file-object-coverage parsed [dict get $r capabilities object_declarations]
check indexed-file-object-diagnostic {} [codes $r]
check indexed-file-object-recovery {{{signal hidden : bit;} parsed} {{signal kept : bit;} parsed}} [objects $r]
set file [lindex [dict get [lindex [dict get $r object_declarations] 0] declarations] 0]
check indexed-file-diagnostic FILE_OBJECT_MISSING_SEMICOLON [dict get [lindex [dict get $file diagnostics] 0] code]
set r [analyze constraining {entity e is
    signal p : integer range 0 to 2
    type color is (red, blue);
    signal kept : bit;
end;}]
check constraint-separator {OBJECT_MISSING_SEMICOLON} [codes $r]
check constraint-extent {{signal p : integer range 0 to 2} malformed} [lindex [objects $r] 0]
set r [analyze unsafe {entity e is
    constant c : integer := 0
    type is (a, b) signal hidden : bit;
    signal kept : bit;
end;}]
check unsafe-status unrecognized [dict get $r capabilities object_declarations]
check unsafe-diagnostic OBJECT_UNPROVEN_DECLARATION_BOUNDARY [lindex [codes $r] 0]
check unsafe-following-sibling {{signal kept : bit;} parsed} [lindex [objects $r] end]
check unsafe-object-count 2 [llength [objects $r]]

set r [analyze lexical {
entity e is
    constant a : string := "type t is (a, b); subtype x is integer; file f : text;";
    constant b : character := character'(';');
    constant c : integer := integer'(0); -- procedure p; signal bogus : bit;
    constant d : integer := (1 + (2 * 3));
    constant v : bit_vector(3 downto 0) := "1010";
    subtype digits is integer range v'range;
    subtype vector_type is v'subtype;
    signal s : bit;
end;
}]
check lexical-status parsed [dict get $r capabilities object_declarations]
check lexical-diagnostics {} [codes $r]
check lexical-object-count 6 [llength [objects $r]]
puts [list Tcl [info patchlevel] assertions $assertions failures $failures]
exit [expr {$failures > 0}]
