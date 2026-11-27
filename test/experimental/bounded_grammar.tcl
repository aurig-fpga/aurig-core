# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
source [file join $core experimental vhdl bounded.tcl]
set fixture [file join $tests fixtures bounded-grammar.vhd.fixture]
set result [::vhdl_index::bounded::read $fixture 2008]
lassign [::vhdl_index::bounded::interval [dict get $result tape] {0 9}] first last
set parsed [::vhdl_index::bounded::parse [dict get $result snapshot] [dict get $result tape] 2008 expression $first $last]
if {[dict get $parsed status] ne "parsed"} {error "Expected a complete expression: $parsed"}
set top [::vhdl_index::bounded::node $parsed [dict get $parsed root]]
if {[dict get $top kind] ne "binary" || [dict get $top connectors] ne {{+ 2 3}}} {
    error "Unexpected precedence root: $top"
}

proc equal {actual expected label} {
    if {$actual ne $expected} {error "$label: expected <$expected>, observed <$actual>"}
}

proc ast {parsed id} {
    set node [::vhdl_index::bounded::node $parsed $id]
    set output [list [dict get $node kind]]
    foreach op [dict get $node connectors] {lappend output [lindex $op 0]}
    foreach child [dict get $node children] {lappend output [ast $parsed $child]}
    return $output
}

proc roots {parsed} {
    return [::vhdl_index::bounded::node $parsed [dict get $parsed root]]
}

proc check_rows {snapshot tape parsed} {
    lassign [dict get $parsed span] first last
    set id 0
    foreach row [dict get $parsed rows] {
        lassign $row kind start end children connectors candidates
        if {$start < $first || $end > $last || $start >= $end} {error "Invalid row extent: $row"}
        foreach child $children {
            lassign [lindex [dict get $parsed rows] $child] childKind left right
            if {$child >= $id || $left < $start || $right > $end} {error "Invalid child of $row"}
        }
        set previous $start
        foreach connector $connectors {
            lassign $connector label left right
            if {$left < $previous || $right > $end} {error "Invalid connector in $row"}
            lassign [::vhdl_index::bounded::interval $tape [list $left $right]] ordinal after
            equal $after [expr {$ordinal + 1}] "connector token extent"
            equal [::vhdl_index::lexer::token $tape [lindex [dict get $tape significant] $ordinal]] \
                $connector "connector source accounting"
            set previous $right
        }
        incr id
    }
    equal [dict get [roots $parsed] span] [dict get $parsed span] "complete extent"
    equal [dict get $parsed diagnostics] {} "complete diagnostics"
}

proc on_line {input line edition {entry expression} {limits {}}} {
    set snapshot [dict get $input snapshot]
    set tape [dict get $input tape]
    set lines [dict get $snapshot line_starts]
    set left [lindex $lines [expr {$line - 1}]]
    set right [lindex $lines $line]
    lassign [::vhdl_index::bounded::interval $tape [list $left $right]] first last
    set parsed [::vhdl_index::bounded::parse $snapshot $tape $edition $entry $first $last $limits]
    if {[dict get $parsed complete]} {
        check_rows $snapshot $tape $parsed
        equal [::vhdl_index::slice $snapshot [dict get $parsed span]] \
            [string trim [::vhdl_index::slice $snapshot [list $left $right]]] "full source reconstruction"
    }
    return $parsed
}

set exact {
    1 {binary + identifier {binary * identifier identifier}}
    2 {logical and {logical and {relation <= {shift sll {binary & {binary + {sign - {binary * {binary ** number number} number}} number} identifier} number} identifier} identifier} identifier}
    3 {binary * {unary abs identifier} {unary not identifier}}
    4 {logical or {group ( ) {logical and identifier identifier}} {group ( ) {logical nor identifier identifier}}}
    5 {relation ?<= identifier identifier}
    6 {condition ?? {group ( ) {logical and identifier identifier}}}
    7 {reduction xor identifier}
    8 {binary * {group ( ) {binary + identifier identifier}} identifier}
    15 {slice ( ) identifier {range downto number number}}
    16 {slice ( ) identifier {parameterized_range_attribute ( ) {range_attribute ' identifier identifier} number}}
    17 {attribute ' {selected . {dereference . {selected . identifier identifier} all} identifier} identifier}
    19 {selected_character . identifier character}
    20 {qualified ' identifier {group ( ) {binary + identifier identifier}}}
    21 {qualified ' identifier {aggregate ( , ) {element | => {choice number} {choice number} {aggregate ( , ) {element identifier} {element identifier}}} {element => others {aggregate ( , ) {element identifier} {element identifier}}}}}
    22 {aggregate ( , ) {element {aggregate ( , ) {element identifier} {element identifier}}} {element {aggregate ( ) {element => others identifier}}}}
    23 {physical number identifier}
    24 {physical number {selected . {selected . identifier identifier} identifier}}
    25 number
    26 bit_string
    27 bit_string
    28 {qualified ' identifier {group ( ) character_literal}}
    29 string
    30 extended_identifier
    31 {external << signal : >> {relative_path ^ . ^ . . {generate_path ( ) identifier number} identifier} {subtype {selected . identifier identifier} {constraint ( ) {range downto number number}}}}
    32 {external << constant : >> {package_path @ . . identifier identifier identifier} {subtype identifier}}
    33 {external << variable : >> {absolute_path . . identifier identifier} {subtype range identifier {range to number number}}}
    34 {allocator new {subtype {selected . {selected . identifier identifier} identifier}}}
    35 {allocator new {qualified ' identifier {aggregate ( ) {element => others character_literal}}}}
    36 {allocator new {subtype identifier {constraint ( ) {range downto number number}}}}
    37 {allocator new {subtype identifier {constraint ( ) open} {constraint ( ) {range downto number number}}}}
    38 {name_suffix ( , ) identifier number {actual_association => identifier {aggregate ( , ) {element identifier} {element identifier}}}}
    39 {selected . {name_suffix ( ) identifier {actual_association => identifier identifier}} identifier}
    42 {name_suffix ( ) {attribute ' identifier identifier} number}
    43 {qualified ' {subtype_attribute ' {selected . identifier identifier} subtype} {group ( ) number}}
}
foreach {line expected} $exact {
    set parsed [on_line $result $line 2008]
    equal [dict get $parsed complete] 1 "line $line complete: [dict get $parsed diagnostics]"
    equal [ast $parsed [dict get $parsed root]] $expected "line $line tree"
}
foreach {line expected} {
    9 {indexed slice function_call type_conversion}
    10 {indexed slice function_call type_conversion}
    11 {indexed slice function_call type_conversion}
    12 {indexed function_call}
    13 function_call
    14 function_call
    15 slice
    42 {indexed function_call attribute_parameter}
} {
    set parsed [on_line $result $line 2008]
    equal [dict get [roots $parsed] candidates] $expected "line $line candidates"
    equal [dict get $parsed status] [expr {[llength $expected] > 1 ? "ambiguous" : "parsed"}] "line $line status"
}
set parsed [on_line $result 18 2008 name]
set signature [lindex [dict get [roots $parsed] children] 1]
equal [ast $parsed $signature] [list signature {[} , return {]} type_mark type_mark return_type_mark] "signature"
equal [dict get [::vhdl_index::bounded::node $parsed $signature] identity] \
    [list [dict get $parsed source_id] [dict get $parsed token_interval] name $signature] "node identity"
set parsed [on_line $result 9 2008 name]
equal [dict get [roots $parsed] candidates] {indexed slice} "strict name candidates"
set parsed [on_line $result 13 2008 name]
equal [dict get $parsed complete] 0 "strict name rejects a bare call-only form"
set parsed [on_line $result 40 2008]
set inner [lindex [dict get [roots $parsed] children] 0]
equal [dict get [::vhdl_index::bounded::node $parsed $inner] candidates] \
    {indexed slice function_call} "conversion cannot be a selected-name prefix"
set parsed [on_line $result 41 2008]
equal [dict get [roots $parsed] candidates] indexed "returned value cannot itself be called"

if {[info exists ::env(AURIG_EXPERIMENTAL_SCRATCH)]} {
    set scratch $::env(AURIG_EXPERIMENTAL_SCRATCH)
} else {
    set scratch [file join /tmp aurig-bounded-[pid]]
}
file mkdir $scratch
set transient [file join $scratch case.vhd.fixture]
proc probe {text edition {entry expression} {limits {}} {lexLimits {}}} {
    global transient
    set handle [open $transient wb]
    fconfigure $handle -encoding utf-8 -translation lf
    puts -nonewline $handle $text
    close $handle
    set input [::vhdl_index::bounded::read $transient $edition $lexLimits]
    set tape [dict get $input tape]
    set last [expr {[llength [dict get $tape significant]] - 1}]
    return [::vhdl_index::bounded::parse [dict get $input snapshot] $tape $edition $entry 0 $last $limits]
}

set malformed {
    {a ** b ** c} {a ** -b} {a ** not b} {not not a} {abs a ** b}
    {a * -b} {a + +b} {a + -b} {a sll b srl c} {a < b = c}
    {a and b or c} {a nand b nand c} {a nor b nor c} {a xor b xnor c}
    {?? a and b} {a and ?? b} {?? ?? a} {a ?= b = c}
    {a +} {pkg.} {f()} {f(x y)} {f(,x)} {f(x,)} {f((a, b)} {f(x =>)}
    {f(x => a, b)} {f(a + b => c)} {f(inertial x)} {f(open to 1)}
    {(x = y => a)} {(others | 1 => a)} {(1 | others => a)}
    {(others => a, b)} {(0 => a, b)} {(a, b,)} {t'()} {t'('x'} {a[bit]}
    {a(0 to)} {a(0 to 1, 2)} {a(1) @ x} {a'length()} {a'range(1,2)}
    {<< signal @lib.x : t >>} {<< signal a(2) : t >>} {<< file a : integer >>}
    {<< variable ^a : integer >>} {<< signal x : t >} {<< signal x : t >> overlap}
    {new t range 1 to 2} {new f t} {new vec(1 to )} {new t'}
    {16#G#} {23E-3} {16#D#e-2} {a__b} {3ns} {"unterminated} {a + `if}
}
foreach source $malformed {
    set parsed [probe $source 2008]
    equal [dict get $parsed complete] 0 "rejected: $source"
    equal [dict get $parsed rows] {} "no unproved rows: $source"
    if {[dict get $parsed diagnostics] eq {} || [dict get $parsed unresolved] eq {}} {
        error "Missing evidence: $source"
    }
    puts "reject [list $source] [dict get $parsed status] [dict get $parsed diagnostics]"
}
foreach source {{a ?= b} {?? x} {or x} {<< signal x : t >>} {new x(open)}} {
    foreach edition {1993 2002} {
        equal [dict get [probe $source $edition] complete] 0 "edition $edition $source"
    }
    equal [dict get [probe $source 2008] complete] 1 "edition 2008 $source"
}
foreach op {and or nand nor xor xnor} {
    equal [dict get [probe "$op x" 2008] complete] 1 "reduction $op"
    equal [dict get [probe "$op x $op y" 2008] status] unsupported "reduction grouping $op"
    equal [dict get [probe "($op x) $op ($op y)" 2008] complete] 1 "grouped reductions $op"
}
foreach op {= /= < <= > >= ?= ?/= ?< ?<= ?> ?>= sll srl sla sra rol ror * / mod rem + - & ** and or nand nor xor xnor} {
    equal [dict get [probe "x $op y" 2008] complete] 1 "operator $op"
}
foreach source {{new r(field(2 to 3))} {<< signal x : (resolve) std_logic_vector >>}} {
    equal [dict get [probe $source 2008] status] unsupported "explicit unsupported $source"
}
foreach edition {1993 2002 2008} {
    set historical [probe {0 to 3 natural} $edition discrete_range]
    equal [ast $historical [dict get $historical root]] {range to number {physical number identifier}} "historical range"
    equal [dict get [probe {f[return boolean]'simple_name} $edition name] complete] 1 "signature $edition"
    equal [dict get [probe {a nor b} $edition] complete] 1 "older binary $edition"
}
set flat [join [lrepeat 4096 x] { + }]
set parsed [probe $flat 1993 expression {depth 1}]
equal [llength [dict get $parsed rows]] 8191 "flat nodes"
set next [dict get $parsed root]
for {set count 4095} {$count > 0} {incr count -1} {
    set top [::vhdl_index::bounded::node $parsed $next]
    equal [dict get $top kind] binary "left-associative flat chain"
    lassign [dict get $top children] next right
    equal [dict get [::vhdl_index::bounded::node $parsed $right] kind] identifier "flat right child"
}
equal [dict get [probe $flat 1993 expression {nodes 80}] status] unavailable "node limit"
equal [dict get [probe $flat 1993 expression {} {tokens 80}] status] unavailable "token limit"
foreach depth {1 10 32 33 100} {
    set source "[string repeat ( $depth]x[string repeat ) $depth]"
    equal [dict get [probe $source 2008] status] [expr {$depth <= 32 ? "parsed" : "unavailable"}] "depth $depth"
}
set source {f((a, b), x => g(y => word'(others => '1')))}
set base [probe $source 2008]
equal [dict get $base complete] 1 "mutation control"
set tapeInput [::vhdl_index::bounded::read $transient 2008]
set tape [dict get $tapeInput tape]
set snapshot [dict get $tapeInput snapshot]
set end [expr {[llength [dict get $tape significant]] - 1}]
for {set cut 2} {$cut < $end} {incr cut} {
    set prefix [::vhdl_index::bounded::parse $snapshot $tape 2008 expression 0 $cut]
    equal [dict get $prefix complete] 0 "prefix truncation $cut"
    lassign [dict get $prefix span] left right
    foreach issue [dict get $prefix diagnostics] {
        lassign [dict get $issue span] start stop
        if {$start < $left || $stop > $right} {error "Prefix diagnostic crossed its fence: $issue"}
    }
}
for {set ordinal 0} {$ordinal < $end} {incr ordinal} {
    set offset [lindex [dict get $tape significant] $ordinal]
    lassign [::vhdl_index::lexer::token $tape $offset] label start stop
    if {$label ni {=> , ( )}} {continue}
    set mutation [string replace $source $start [expr {$stop - 1}] " "]
    equal [dict get [probe $mutation 2008] complete] 0 "connector mutation $ordinal"
}
set self [probe "x\r\n  -- ;\r\n +  y" 2008]
set top [roots $self]
equal [dict get $top span] {0 14} "CRLF-normalized offset"
equal [dict get $top connectors] {{+ 10 11}} "offset after line trivia"
puts "PASS bounded names, expressions, edition, lexical boundaries, topology, mutation and limits"
