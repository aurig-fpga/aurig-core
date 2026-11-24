# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

set test_dir [file dirname [file normalize [info script]]]
set core_root [file dirname $test_dir]
set auto_path [linsert $auto_path 0 $core_root]
package require aurig::core

namespace eval ::source_test {
    variable dir [file join $::test_dir build "vhdlscan_source-[pid]-[clock clicks]"]
    variable passed 0
    variable failed 0
}

proc ::source_test::equal {label actual expected} {
    variable passed
    variable failed
    if {$actual eq $expected} {
        incr passed
    } else {
        puts "FAIL $label: expected <$expected>, got <$actual>"
        incr failed
    }
}

proc ::source_test::fixture {name bytes} {
    variable dir
    set path [file join $dir "$name.vhd"]
    set channel [open $path wb]
    puts -nonewline $channel $bytes
    close $channel
    return $path
}

proc ::source_test::scan {path lint} {
    ::aurig::core::analyze::vhdlscan -in $path -lint $lint
}

proc ::source_test::entities {ast} {
    set result {}
    foreach entity [dict get $ast entities] {
        lappend result [list [dict get $entity name] [dict get $entity line]]
    }
    return $result
}

proc ::source_test::check_design {label ast payload} {
    equal "$label entities" [entities $ast] {{Dut 5} {Other 15}}
    equal "$label context" [list [dict get [lindex [dict get $ast libraries] 0] name] \
        [dict get [lindex [dict get $ast libraries] 0] line] \
        [dict get [lindex [dict get $ast uses] 0] line]] {ieee 2 3}
    equal "$label first comment" [dict get $ast comments line 1 comment] "heading $payload"
    equal "$label design comment" [dict get $ast comments line 4 comment] "$payload entity Ghost"
    equal "$label attached comment" [dict get [lindex [dict get $ast entities] 0] comment] "$payload entity Ghost"
    equal "$label architecture count" [llength [dict get $ast architectures]] 1
    set architecture [lindex [dict get $ast architectures] 0]
    equal "$label architecture" [list [dict get $architecture name] [dict get $architecture entity] \
        [dict get $architecture line]] {rtl Dut 9}
    equal "$label architecture comment" [dict get $ast comments line 8 comment] {rtl comment}
    set literal [lindex [dict get $architecture declarations] 0]
    equal "$label declaration" [list [dict get $literal kind] [dict get $literal name] \
        [dict get $literal line]] {constant Message 10}
    equal "$label literal" [dict get [lindex [dict get $literal args] 0] init] "\"$payload entity Ghost -- here\""
    equal "$label report literal" [expr {[string first "report \"architecture Glow $payload\"" \
        [dict get $architecture body_section]] >= 0}] 1
    equal "$label metadata keys" [dict keys [dict get $ast meta]] {file parsed_at sha1}
}

proc ::source_test::check_error {label path lint expected details} {
    set rc [catch {scan $path $lint} result options]
    equal "$label error raised" $rc 1
    if {$rc == 1} {
        equal "$label error code" [dict get $options -errorcode] $expected
        equal "$label error identifies source" [expr {[string first $path $result] >= 0}] 1
        equal "$label error detail" [expr {[string first $details $result] >= 0}] 1
    } else {
        puts "  returned entities [entities $result]"
    }
}

proc ::source_test::check_io {path} {
    set core [interp create]
    $core eval [list set auto_path $::auto_path]
    $core eval [list set path $path]
    $core eval {package require aurig::core}
    $core eval {
        set initial [lsort [file channels]]
        rename ::open ::test_open
        rename ::read ::test_read
        proc ::open {path mode} {
            if {$::stage eq "OPEN"} {
                return -code error -errorcode {TEST OPEN} {injected open error}
            }
            set ::source_channel [::test_open $path $mode]
            return $::source_channel
        }
        proc ::read {channel} {
            if {$::stage eq "READ"} {
                return -code error -errorcode {TEST READ} {injected read error}
            }
            return [::test_read $channel]
        }
    }
    foreach stage {OPEN READ} {
        $core eval [list set stage $stage]
        lassign [$core eval {
            set rc [catch {::aurig::core::analyze::vhdlscan -in $path} result opts]
            list $rc $result $opts [lsort [file channels]] $initial
        }] rc result opts after before
        equal "$stage raises" $rc 1
        equal "$stage includes path" [expr {[string first $path $result] >= 0}] 1
        equal "$stage preserves detail" [expr {[string first "injected [string tolower $stage] error" $result] >= 0}] 1
        equal "$stage structured category" [dict get $opts -errorcode] [list AURIG CORE SOURCE IO $stage [list TEST $stage]]
        equal "$stage channel cleanup" $after $before
    }
    interp delete $core
}

proc ::source_test::run {} {
    set bom [binary format H* efbbbf]
    set bad [binary format H* 80]
    set single "entity Dut is\nend entity Dut;"
    set two "$single\nentity Other is\nend entity Other;\n"
    set simple [list [fixture plain "$single\n"] [fixture bom "$bom$single\n"] \
        [fixture bom_no_final_newline "$bom$single"] [fixture plain_no_final_newline $single]]
    set empty [list [fixture empty ""] [fixture bom_only $bom]]
    set design {-- heading PAYLOAD
library ieee;
use ieee.std_logic_1164.all;
-- PAYLOAD entity Ghost
entity Dut is
end entity Dut;

-- rtl comment
architecture rtl of Dut is
    constant Message : string := "PAYLOAD entity Ghost -- here";
begin
    assert false report "architecture Glow PAYLOAD";
end architecture rtl;

entity Other is
end entity Other;}
    set designs {}
    set payload "caf\u00e9 \u20ac"
    foreach {codec eol sign} {utf-8 lf none utf-8 crlf bom utf-8 cr bom cp1252 crlf none} {
        set hex [dict get {utf-8 636166c3a920e282ac cp1252 636166e92080} $codec]
        set raw [string map [list PAYLOAD [binary format H* $hex] "\n" \
            [dict get {lf "\n" crlf "\r\n" cr "\r"} $eol]] $design]
        if {$sign eq "bom"} {set raw "$bom$raw"}
        lappend designs [fixture "design_${codec}_${eol}_$sign" $raw]
    }
    set context [fixture bom_before_context "${bom}library ieee;\n$single"]
    set signed_bad [fixture signed_bad "$bom-- x\r\n$bad\n$two"]
    set embedded_nul [fixture embedded_nul "-- x\x00y\r\n$two"]
    set prefixed_single [fixture prefixed_single "$bad$single"]
    set prefixed_multi [fixture prefixed_multi "-- [binary format H* e9] entity Ghost\r\n$bad$two"]
    set prefixed_arch [fixture prefixed_arch "$single\n${bad}architecture rtl of Dut is\nbegin\nend architecture rtl;\n"]
    set prefixed_package [fixture prefixed_package "${bad}package Pack is\nend package Pack;\n"]
    set unsupported [fixture unsupported "-- [binary format H* e9] architecture Ghost\ncontext work.missing;\n$two"]
    set ascii_prefix [fixture ascii_prefix "x$single\n"]
    set prefixed_context [fixture prefixed_context "${bad}context work.missing;\n$two"]
    set prefixed_unclosed [fixture prefixed_unclosed "${bad}entity Unclosed is\n"]

    foreach system {utf-8 cp1252} {
        encoding system $system
        foreach lint {false true} {
            foreach path $simple {
                set ast [scan $path $lint]
                equal "$system $lint [file tail $path]" [entities $ast] {{Dut 1}}
                equal "$system $lint [file tail $path] architectures" [dict get $ast architectures] {}
            }
            foreach path $empty {
                set ast [scan $path $lint]
                equal "$system $lint [file tail $path]" [list [entities $ast] [dict get $ast architectures]] {{} {}}
            }
            foreach path $designs {
                check_design "$system $lint [file tail $path]" [scan $path $lint] $payload
            }
            set ast [scan $context $lint]
            set library_lines {}
            foreach library [dict get $ast libraries] {
                lappend library_lines [dict get $library line]
            }
            equal "$system $lint BOM before context" [list $library_lines [entities $ast]] {1 {{Dut 2}}}
            equal "$system $lint unrelated unsupported context" [entities [scan $unsupported $lint]] {{Dut 3} {Other 5}}
            equal "$system $lint ASCII unmatched source" [entities [scan $ascii_prefix $lint]] {}
            equal "$system $lint prefixed unsupported context" [entities [scan $prefixed_context $lint]] {{Dut 2} {Other 4}}
            equal "$system $lint prefixed unclosed header" [entities [scan $prefixed_unclosed $lint]] {}
            check_error "$system $lint signed invalid UTF-8" $signed_bad $lint {AURIG CORE SOURCE INVALID_UTF8 9} {byte 9}
            check_error "$system $lint embedded NUL" $embedded_nul $lint {AURIG CORE SOURCE NUL 4} {byte 4}
            check_error "$system $lint single prefixed entity" $prefixed_single $lint {AURIG CORE SOURCE UNIT_PREFIX 1 0} {line 1}
            check_error "$system $lint multiple entities with prefix" $prefixed_multi $lint {AURIG CORE SOURCE UNIT_PREFIX 2 3} {line 2}
            check_error "$system $lint prefixed architecture" $prefixed_arch $lint {AURIG CORE SOURCE UNIT_PREFIX 3 30} {line 3}
            check_error "$system $lint prefixed package" $prefixed_package $lint {AURIG CORE SOURCE UNIT_PREFIX 1 0} {line 1}
        }
    }
    check_io [lindex $simple 0]
}

fconfigure stdout -encoding utf-8 -translation lf
set previous_encoding [encoding system]
file mkdir $::source_test::dir
set rc [catch {::source_test::run} result options]
encoding system $previous_encoding
file delete -force -- $::source_test::dir
if {$rc} {return -options $options $result}
puts "vhdlscan source encoding: $::source_test::passed PASS, $::source_test::failed FAIL on Tcl [info patchlevel]"
exit [expr {$::source_test::failed != 0}]
