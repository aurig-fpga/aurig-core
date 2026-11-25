source [file join [file dirname [info script]] startup.tcl]
set fixtureDir [file join $task fixtures]
set archived [file join $workspace _tasks AURIG-004-A fixtures]
set scratch [file join $task scratch]
set assertions 0
set failures 0

proc equal {message expected actual} {
    incr ::assertions
    if {$expected ne $actual} {
        incr ::failures
        puts [list FAIL $message expected $expected actual $actual]
    }
}

proc result_for {path edition args} {
    return [::vhdl_index::analyze_file $path $edition {*}$args]
}

proc file_text {path content} {
    set out [open $path wb]
    puts -nonewline $out $content
    close $out
}

proc inline {name text {edition 2008} args} {
    set path [file join $::scratch $name.vhd]
    file_text $path [encoding convertto utf-8 $text]
    return [result_for $path $edition {*}$args]
}

proc inventory {result {fold 0}} {
    set output {}
    foreach unit [dict get $result units] {
        set name [dict get $unit name]
        if {$fold} {set name [string tolower $name]}
        lappend output "[dict get $unit kind]:$name"
    }
    return $output
}

proc diagnoses {result} {
    set codes {}
    foreach area {lexical_diagnostics structural_diagnostics} {
        foreach diagnostic [dict get $result $area] {
            lappend codes [dict get $diagnostic code]
        }
    }
    return $codes
}

proc context {result unitIndex {key context}} {
    set source [dict get $result snapshot]
    set unit [lindex [dict get $result units] $unitIndex]
    set output {}
    foreach clause [dict get $unit $key] {
        set selected {}
        foreach name [dict get $clause names] {
            lappend selected [::vhdl_index::slice $source [dict get $name span]]
        }
        lappend output [list [dict get $clause kind] $selected]
    }
    return $output
}

proc assertions_for_source {result tag} {
    set source [dict get $result snapshot]
    set size [dict get $source length]
    set tape [dict get $result tape]
    set count [llength [dict get $tape starts]]
    set consumed 0
    set reconstructed {}
    set line 0
    set referenceLine 1
    set referenceStart 0
    for {set i 0} {$i < $count} {incr i} {
        lassign [::vhdl_index::lexer::token $tape $i] kind start end
        equal "$tag tape adjacency $i" $consumed $start
        set consumed $end
        if {$i < $count - 1} {
            equal "$tag nonempty $i" 1 [expr {$end > $start && $kind ne "eof"}]
        } else {
            equal "$tag EOF" [list eof $size $size] [list $kind $start $end]
        }
        set piece [::vhdl_index::slice $source [list $start $end]]
        set expected [list $referenceLine [expr {$start - $referenceStart}]]
        equal "$tag random position $i" $expected [::vhdl_index::position $source $start]
        equal "$tag sequential position $i" $expected [::vhdl_index::next_position $source $start line]
        set n [regexp -all {\n} $piece]
        if {$n > 0} {
            incr referenceLine $n
            set referenceStart [expr {$start + [string last "\n" $piece] + 1}]
        }
        append reconstructed $piece
    }
    equal "$tag tape exact reconstruction" [dict get $source text] $reconstructed
    set consumed 0
    set reconstructed {}
    foreach record [dict get $result ledger] {
        lassign $record status start end
        equal "$tag ledger adjacency" $consumed $start
        equal "$tag ledger nonempty" 1 [expr {$end > $start}]
        append reconstructed [::vhdl_index::slice $source [list $start $end]]
        set consumed $end
    }
    equal "$tag ledger EOF" $size $consumed
    equal "$tag ledger exact reconstruction" [dict get $source text] $reconstructed
    equal "$tag accounting" parsed [dict get $result capabilities accounting]
    equal "$tag identity" [dict get $source id] [dict get $result source_id]
    set previous 0
    foreach unit [dict get $result units] {
        lassign [dict get $unit span] start end
        lassign [dict get $unit header_span] headerStart headerEnd
        lassign [dict get $unit name_span] nameStart nameEnd
        lassign [dict get $unit terminator_span] tailStart tailEnd
        equal "$tag unit span relationship" 1 [expr {$previous <= $start && $start == $headerStart &&
            $start < $nameStart && $nameStart < $nameEnd && $nameEnd < $headerEnd &&
            $headerEnd <= $tailStart && $tailStart < $end && $tailEnd == $end}]
        equal "$tag name slice" [dict get $unit name] [::vhdl_index::slice $source [dict get $unit name_span]]
        equal "$tag terminator ends at semicolon" ";" [::vhdl_index::slice $source [list [expr {$end-1}] $end]]
        set previous $end
    }
}

set file [open [file join $fixtureDir archived-expectations.tsv]]
while {[gets $file row] >= 0} {
    lassign [split $row "\t"] name editions expected
    set expected [split $expected " "]
    foreach edition [split $editions ,] {
        set result [result_for [file join $archived $name.vhd] $edition]
        set tag "$name/$edition"
        equal "$tag inventory" [lsearch -all -inline -not -glob $expected !*] [inventory $result]
        set codes {}
        foreach code [lsearch -all -inline -glob $expected !*] {lappend codes [string range $code 1 end]}
        equal "$tag diagnostics" $codes [diagnoses $result]
        assertions_for_source $result $tag
    }
}
close $file

set oneLine [inline exact {library work; entity A is end; use work.p.all; entity B is end entity B;}]
set source [dict get $oneLine snapshot]
lassign [dict get $oneLine units] a b
equal exact-inventory {entity:A entity:B} [inventory $oneLine]
equal exact-a-name {21 22} [dict get $a name_span]
equal exact-a-unit {14 30} [dict get $a span]
equal exact-a-header {14 25} [dict get $a header_span]
equal exact-a-terminator {26 30} [dict get $a terminator_span]
equal exact-b-name {54 55} [dict get $b name_span]
equal exact-b-unit {47 72} [dict get $b span]
equal exact-b-terminator {59 72} [dict get $b terminator_span]
equal exact-name-column {1 54} [::vhdl_index::position $source 54]
equal exact-owner-a {{library work}} [context $oneLine 0]
equal exact-owner-b {{use work.p.all}} [context $oneLine 1]
equal exact-owner-span {31 46} [dict get [lindex [dict get $b context] 0] span]
equal exact-target-spans {{35 39} {40 41} {42 45}} \
    [dict get [lindex [dict get [lindex [dict get $b context] 0] names] 0] components]
assertions_for_source $oneLine exact

foreach {name edition index key expected} {
    i66-context 2008 0 context {}
    i66-context 2008 0 context_items {{library ieee} {use ieee.std_logic_1164.all}}
    i85-context-use 2008 0 context {{context work.ctx}}
    i85-multi-library 1993 0 context {{library {ieee work}}}
    i64-multi-use 1993 0 context {{library ieee} {use {ieee.std_logic_1164.all std.textio.all}}}
    i87-2 1993 1 context {{use work.p.all}}
    i65-local-use 2008 1 context {}
} {
    set result [result_for [file join $archived $name.vhd] $edition]
    equal "context $name/$index/$key" $expected [context $result $index $key]
}
foreach name {i72-short-generate-body i93-1 i93-2 i93-3 i95-3} {
    set result [result_for [file join $archived $name.vhd] 2008]
    set last [lindex [dict get $result units] end]
    set text [dict get $result snapshot text]
    equal "last unit extends through final semicolon $name" [expr {[string last ";" $text] + 1}] [lindex [dict get $last span] 1]
}
set result [result_for [file join $archived i72-short-generate-body.vhd] 2008]
equal "following process remains inside architecture" 1 \
    [expr {[string first {p_after : process} [::vhdl_index::slice [dict get $result snapshot] \
        [dict get [lindex [dict get $result units] 1] opaque]]] >= 0}]

foreach {file edition expected} {
    configuration 1993 {entity:leaf architecture:rtl entity:top architecture:rtl configuration:configured}
    configuration 2002 {entity:leaf architecture:rtl entity:top architecture:rtl configuration:configured}
    configuration 2008 {entity:leaf architecture:rtl entity:top architecture:rtl configuration:configured}
    structure08 2008 {context:c1 context:c2 entity:E architecture:RTL package:template package_instantiation:instance}
    lexical93 1993 EXTENDED_PACKAGE
    lexical93 2002 EXTENDED_PACKAGE
    editions 1993 {entity:protected entity:context entity:procedural entity:reference}
    protected02 2002 {package:counters package_body:counters}
    protected02 2008 {package:counters package_body:counters}
    operators08 2008 {entity:e architecture:rtl}
} {
    set result [result_for [file join $fixtureDir $file.vhd] $edition]
    if {$file eq "lexical93"} {
        set expected [list "package:\\Escaped\\\\;End\\"]
    }
    equal "$file/$edition inventory" $expected [inventory $result]
    equal "$file/$edition diagnostics" {} [diagnoses $result]
    assertions_for_source $result "$file/$edition"
    if {$file eq "structure08"} {
        equal "multi-context ownership" {{context {work.c1 work.c2}}} [context $result 2]
        equal "instantiation is bounded" recognized-but-unsupported [dict get [lindex [dict get $result units] end] status]
        equal "instantiation terminator" ";" [::vhdl_index::slice [dict get $result snapshot] \
            [dict get [lindex [dict get $result units] end] terminator_span]]
    }
}

proc token_expectations {pairs} {
    set result {}
    foreach pair $pairs {lappend result [list {*}$pair]}
    return $result
}

proc selected_tokens {result wanted} {
    set source [dict get $result snapshot]
    set tape [dict get $result tape]
    set selected {}
    for {set i 0} {$i < [llength [dict get $tape starts]]} {incr i} {
        lassign [::vhdl_index::lexer::token $tape $i] type start end
        if {$type in $wanted} {
            lappend selected [list $type [::vhdl_index::slice $source [list $start $end]]]
        }
    }
    return $selected
}

set result [result_for [file join $fixtureDir lexical93.vhd] 1993]
equal "tick, qualified literals, selected Latin-1 names and alternate delimiters" \
    [token_expectations {{' '} {character 'x'} {' '} {character '"'} {character '"'} {character '''} \
        {number 16:Af:} {string {%end %% entity%}} {bit_string X%FE%} {number 3} {' '}}] \
    [selected_tokens $result {' character number string bit_string}]
set result [result_for [file join $fixtureDir operators08.vhd] 2008]
equal "external name and matching operator lexemes" [token_expectations {{<< <<} {>> >>} {number 16#FF#} {number 2#1.01#E-2} {?= ?=}}] \
    [selected_tokens $result {<< >> ?= number}]
set result [result_for [file join $fixtureDir structure08.vhd] 2008]
equal "sized bit literal" [token_expectations {{bit_string 4UX"F"}}] [selected_tokens $result {bit_string}]
foreach {name text expected} {
    context {entity context is end;} {1993 2002}
    protected {entity protected is end;} {1993}
    procedural {entity procedural is end;} {1993 2008}
    reference {entity reference is end;} {1993 2008}
    assume {entity assume is end;} {1993 2002}
    fairness {entity fairness is end;} {1993 2002}
    fair {entity fair is end;} {1993 2002 2008}
    private {entity private is end;} {1993 2002 2008}
} {
    set accepted {}
    foreach edition {1993 2002 2008} {
        set result [inline word-$name $text $edition]
        if {[diagnoses $result] eq {}} {lappend accepted $edition}
    }
    equal "edition spelling $name" $expected $accepted
}
foreach edition {1993 2002} {
    set result [result_for [file join $archived i92-1.vhd] $edition]
    equal "block comments unavailable in $edition" {} [selected_tokens $result {block_comment}]
    equal "no invented units in older edition" {} [inventory $result]
}
set result [inline comments {/* /* entity fake is end; */ entity e is end; -- entity phantom is end;}]
equal "nonnesting comments" entity:e [inventory $result]
equal "comment spelling" {{block_comment {/* /* entity fake is end; */}} {line_comment {-- entity phantom is end;}}} \
    [selected_tokens $result {block_comment line_comment}]
set result [inline trivia "-- VT\ventity\tX is\fend;\n"]
equal "VT and FF separator" entity:X [inventory $result]
equal "physical columns use LF" {1 13} [::vhdl_index::position [dict get $result snapshot] 13]
assertions_for_source $result trivia

set bytes [binary format H* efbbbf2d2df09f98800d0a656e7469747920412069730d656e643b0d0a]
set path [file join $scratch normalized.vhd]
file_text $path $bytes
set result [result_for $path 2008]
set source [dict get $result snapshot]
equal "BOM removed" 1 [dict get $source bom_removed]
equal "supplementary native width and CRLF contraction" {0 5 17 22} [dict get $source line_starts]
equal "name after supplementary and CRLF" {12 13} [dict get [lindex [dict get $result units] 0] name_span]
equal "supplementary comment width" 4 [string length [::vhdl_index::slice $source {0 4}]]
equal "surrogate pair value" d83dde00 [string tolower [format %04x%04x \
    [scan [string index [dict get $source text] 2] %c] [scan [string index [dict get $source text] 3] %c]]]
assertions_for_source $result normalized
set other [result_for $path 2008]
equal "analysis-local identity differs" 1 [expr {[dict get $result source_id] ne [dict get $other source_id]}]

foreach {name hex expect} {
    nul 4120420043 {AURIG CORE SOURCE NUL 3}
    invalidbom efbbbf2d2df09f41 {AURIG CORE SOURCE INVALID_UTF8 5}
} {
    set path [file join $scratch $name.vhd]
    file_text $path [binary format H* $hex]
    catch {::aurig::core::util::read_vhdl_source $path} before beforeOptions
    catch {result_for $path 2008} after afterOptions
    equal "$name unchanged message" $before $after
    equal "$name error code" $expect [dict get $afterOptions -errorcode]
    equal "$name unchanged code" [dict get $beforeOptions -errorcode] [dict get $afterOptions -errorcode]
}
catch {result_for [file join $scratch no-such-source.vhd] 2008} _ io
equal "fatal IO" {AURIG CORE SOURCE IO OPEN} [lrange [dict get $io -errorcode] 0 4]
catch {result_for [file join $fixtureDir lexical93.vhd] 2019} _ unsupported
equal "unverified edition" {VHDL_INDEX EDITION 2019} [dict get $unsupported -errorcode]

foreach {name expected codes} {
    recover {entity:before_unit entity:damaged entity:after_unit} MISMATCHED_END_NAME
    uncertain entity:before_unit MISMATCHED_END_KIND
} {
    set result [result_for [file join $fixtureDir $name.vhd] 2008]
    equal "$name recovery inventory" $expected [inventory $result]
    equal "$name recovery diagnostics" $codes [diagnoses $result]
    assertions_for_source $result $name
}
foreach {name text expected diagnostic} {
    unmatched {entity e is port (x : bit)); end; entity phantom is end;} {} UNMATCHED_DELIMITER
    truncated {entity e is port (x : bit} {} UNCLOSED_DELIMITER
    truncated-body {entity e is constant n : bit;} {} TRUNCATED_SCOPE
    unknown {bad package p is end; entity phantom is end;} {} UNRECOGNIZED_ROOT
    fake-header {entity e is constant n : bit entity phantom is end entity;} {} UNSAFE_UNIT_BOUNDARY
    wrong-kind {entity e is end package; entity phantom is end;} {} EXPECTED_TOKEN
    wrong-bare {entity e is end other; entity phantom is end;} {} UNCERTAIN_END_NAME
    dangling {library work; -- EOF} {} DANGLING_CONTEXT
    nested {entity a is end; architecture b of a is begin p: process begin if true then null; end process; end; entity phantom is end;} entity:a MISMATCHED_END_KIND
    broken-map {package p is new work.base generic map (1) (2); entity phantom is end;} {} EXPECTED_TOKEN
} {
    set result [inline $name $text]
    equal "$name units" $expected [inventory $result]
    equal "$name diagnostic" $diagnostic [lindex [diagnoses $result] 0]
    assertions_for_source $result $name
}
foreach {name text diagnostic} {
    quoted {package p is constant c : string := "broken} UNTERMINATED_STRING
    extended {entity \missing} UNTERMINATED_EXTENDED_IDENTIFIER
    bitstring {package p is constant c : bit_vector := b"1010} UNTERMINATED_BIT_STRING
    blockcomment {entity e is end; /* entity phantom is end;} UNTERMINATED_BLOCK_COMMENT
    number {entity e is constant x : integer := 2#702#;} INVALID_NUMBER
    separator {entity e is constant x : integer := 22ns; end;} MISSING_SEPARATOR
    directive {entity e is end; `protect entity phantom is end;} UNSUPPORTED_DIRECTIVE
} {
    set result [inline $name $text]
    equal "$name lexical diagnosis" $diagnostic [lindex [diagnoses $result] 0]
    assertions_for_source $result $name
}
foreach {name text limits diagnostic} {
    token-limit {entity first is end; entity later is end;} {tokens 8} TOKEN_LIMIT
    delimiter-limit {entity a is port(x : bit_vector((3) downto 0)); end;} {delimiters 2} DELIMITER_LIMIT
    scope-limit {entity a is end; architecture b of a is begin p : process begin if true then wait; end if; end process; end;} {scopes 2} SCOPE_LIMIT
} {
    set result [inline $name $text 2008 $limits]
    equal "$name diagnostic" $diagnostic [lindex [diagnoses $result] 0]
    assertions_for_source $result $name
}
foreach name {empty comment-only} spelling {{} {-- just trivia}} {
    set result [inline $name $spelling]
    equal "$name no units" {} [inventory $result]
    equal "$name lexical" parsed [dict get $result capabilities lexical]
    assertions_for_source $result $name
}

set manifest [open [file join $task raw generated.tsv]]
while {[gets $manifest row] >= 0} {
    lassign [split $row "\t"] edition relative
    set result [result_for [file join $task $relative] $edition]
    equal "$relative generated inventory" {entity:e architecture:rtl package:p} [inventory $result 1]
    equal "$relative generated diagnostics" {} [diagnoses $result]
    set clauses [context $result 0]
    equal "$relative metamorphic context" {{library std} {use {{std . textio . all} {std . standard . boolean}}}} \
        [regsub -all {\s*--[^\n]*\n\s*|\s+} [string tolower $clauses] { }]
    assertions_for_source $result $relative
}
close $manifest
set manifest [open [file join $task raw mutations.tsv]]
while {[gets $manifest row] >= 0} {
    lassign [split $row "\t"] edition relative expected code
    set result [result_for [file join $task $relative] $edition]
    equal "$relative mutation inventory" $expected [inventory $result]
    equal "$relative mutation diagnostics" $code [lindex [diagnoses $result] 0]
    assertions_for_source $result $relative
}
close $manifest
puts [list runtime [info patchlevel] reader $::vhdl_index::readerPath assertions $assertions failures $failures]
exit [expr {$failures > 0}]
