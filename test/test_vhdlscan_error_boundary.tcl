# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set passed 0
set failed 0
proc check {name condition} {
    global passed failed
    if {[uplevel 1 [list expr $condition]]} {
        puts "PASS: $name"
        incr passed
    } else {
        puts "FAIL: $name"
        incr failed
    }
}

set fixture [file join $script_anchor parser fixtures invalid_syntax synthetic_unbalanced_end.vhd]
set detail {split_arch_decl_body: could not find matching END in chunk. Depth=1 (unbalanced begin/end constructs).}
set rc [catch {::aurig::core::analyze::vhdlscan -in $fixture} message options]
check "public parser rejects the synthetic fixture" {$rc == 1}
check "public parser preserves UNBALANCED_END" {
    [dict get $options -errorcode] eq {AURIG CORE PARSE UNBALANCED_END}
}
check "public parser adds file context and preserves the original detail" {
    $message eq "vhdlscan: $fixture: $detail"
}
check "public parser preserves the splitter error info" {
    [string first $detail [dict get $options -errorinfo]] == 0 &&
    [string first {::aurig::core::analyze::split_arch_decl_body $res} [dict get $options -errorinfo]] >= 0
}

set fp [open $fixture r]
set content [read $fp]
close $fp
set chunk [string range $content [string first "architecture rtl" $content] end]
check "synthetic architecture has a terminal ending matched by the regexp" {
    [regexp -nocase -- $::aurig::core::util::re::re_architecture $chunk]
}
set rc [catch {::aurig::core::analyze::split_arch_decl_body $chunk} message options]
check "direct splitter reports UNBALANCED_END without changing its message" {
    $rc == 1 &&
    [dict get $options -errorcode] eq {AURIG CORE PARSE UNBALANCED_END} &&
    $message eq $detail
}

set rc [catch {::aurig::core::analyze::split_arch_decl_body {signal ready : boolean;}} message options]
check "direct splitter reports MISSING_BEGIN without changing its message" {
    $rc == 1 &&
    [dict get $options -errorcode] eq {AURIG CORE PARSE MISSING_BEGIN} &&
    $message eq {split_arch_decl_body: could not find architecture BEGIN in chunk.}
}

# Isolate injected failures from the parent interpreter and other tests.
set child [interp create]
$child eval [list lappend ::auto_path $aurig_core_root]
$child eval {package require aurig::core}
$child eval {
    rename ::aurig::core::analyze::parse_header_metadata ::original_parse_header_metadata
}
set valid_fixture [file join $script_anchor parser fixtures basic simple_entity.vhd]
$child eval [list set fixture $valid_fixture]

foreach {name code detail expected_code expected_detail} {
    tagged {AURIG CORE PARSE MISSING_BEGIN} {detail without recognizable parser words}
        {AURIG CORE PARSE MISSING_BEGIN} {detail without recognizable parser words}
    untagged NONE {split_arch_decl_body: could not find matching END in chunk. Depth=1 (unbalanced begin/end constructs).}
        {AURIG CORE PARSE PARSE_INTERNAL} {PARSE_INTERNAL: split_arch_decl_body: could not find matching END in chunk. Depth=1 (unbalanced begin/end constructs).}
    foreign {OTHER SUBSYSTEM ERROR} {foreign failure}
        {AURIG CORE PARSE PARSE_INTERNAL} {PARSE_INTERNAL: foreign failure}
    near_prefix {AURIG CORE PARSER MISSING_BEGIN} {near-prefix failure}
        {AURIG CORE PARSE PARSE_INTERNAL} {PARSE_INTERNAL: near-prefix failure}
} {
    $child eval [list set injected_code $code]
    $child eval [list set injected_detail $detail]
    $child eval {
        proc ::aurig::core::analyze::parse_header_metadata {dictVar} {
            return -code error -errorcode $::injected_code \
                -errorinfo {original errorinfo sentinel} $::injected_detail
        }
    }
    lassign [$child eval {
        set rc [catch {::aurig::core::analyze::vhdlscan -in $fixture} message options]
        list $rc $message $options
    }] rc message options
    check "$name failure has the expected error code" {
        $rc == 1 && [dict get $options -errorcode] eq $expected_code
    }
    check "$name failure has the expected contextual message" {
        $message eq "vhdlscan: $valid_fixture: $expected_detail"
    }
    check "$name failure preserves original error info" {
        [string first {original errorinfo sentinel} [dict get $options -errorinfo]] == 0 &&
        [string first {parse_header_metadata parseDict} [dict get $options -errorinfo]] >= 0
    }
}

# The real lint validator must reject this input before the injected helper.
set build_dir [file join $script_anchor build vhdlscan_error_boundary]
file mkdir $build_dir
set lint_fixture [file join $build_dir lint_invalid.vhd]
set fp [open $lint_fixture w]
puts $fp {entity lint_invalid is
    po
rt (
    clk : in bit
);
end lint_invalid;}
close $fp
$child eval [list set fixture $lint_fixture]
lassign [$child eval {
    set rc [catch {::aurig::core::analyze::vhdlscan -in $fixture -lint true} message options]
    list $rc $message $options
}] rc message options
check "lint validation remains outside the parse boundary" {
    $rc == 1 && [dict get $options -errorcode] eq {NONE} &&
    [string first {ERROR: VHDL lint syntax error in lint_invalid.vhd:} $message] == 0 &&
    [string first {keyword port cannot be split across lines} $message] >= 0
}
interp delete $child
file delete -- $lint_fixture

set rc [catch {::aurig::core::analyze::vhdlscan} message options]
check "input validation remains outside the parse boundary" {
    $rc == 1 && [dict get $options -errorcode] eq {NONE} &&
    $message eq {ERROR: No input file provided. Use -in <file> to specify the input VHDL file.}
}

puts "Passed: $passed"
puts "Failed: $failed"
exit [expr {$failed > 0}]
