# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Focused regression tests for lint-only syntax diagnostics.

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set build_dir [file join $aurig_core_root "test" "build" "vhdlscan_lint_diagnostics"]
file delete -force $build_dir
file mkdir $build_dir

set total 0
set passed 0
set failed 0

proc write_fixture {name content} {
    global build_dir
    set path [file join $build_dir $name]
    set fp [open $path w]
    fconfigure $fp -translation lf -encoding utf-8
    puts -nonewline $fp $content
    close $fp
    return $path
}

proc pass {name} {
    global passed
    incr passed
    puts "  \[PASS\] $name"
}

proc fail {name message} {
    global failed
    incr failed
    puts "  \[FAIL\] $name"
    puts "         $message"
}

proc assert_lint_ok {name content} {
    global total
    incr total
    set path [write_fixture "${name}.vhd" $content]
    if {[catch {::aurig::core::analyze::vhdlscan -in $path -verbosity 0 -lint true} err]} {
        fail $name $err
    } else {
        pass $name
    }
}

proc assert_lint_error {name content expected {lint_value true}} {
    global total
    incr total
    set path [write_fixture "${name}.vhd" $content]
    if {[catch {::aurig::core::analyze::vhdlscan -in $path -verbosity 0 -lint $lint_value} err]} {
        if {[string match "*$expected*" $err]} {
            pass $name
        } else {
            fail $name "expected '$expected' in '$err'"
        }
    } else {
        fail $name "expected lint error containing '$expected'"
    }
}

proc assert_lint_keeps_string_comment_marker {name content forbidden_comment} {
    global total
    incr total
    set path [write_fixture "${name}.vhd" $content]
    if {[catch {set parse_result [::aurig::core::analyze::vhdlscan -in $path -verbosity 0 -lint true]} err]} {
        fail $name $err
        return
    }

    set found 0
    if {[dict exists $parse_result comments line]} {
        dict for {line info} [dict get $parse_result comments line] {
            if {[dict exists $info comment] &&
                [string match "*$forbidden_comment*" [dict get $info comment]]} {
                set found 1
                break
            }
        }
    }

    if {$found} {
        fail $name "string-contained comment marker was parsed as a VHDL comment"
    } else {
        pass $name
    }
}

puts "=========================================="
puts "VHDLScan Lint Diagnostic Regression Tests"
puts "=========================================="

assert_lint_ok "end-name-shorthand" {
library ieee;
use ieee.std_logic_1164.all;

entity shorthand_entity is
    port (
        clk : in std_logic
    );
end shorthand_entity;

architecture rtl of shorthand_entity is
begin
end rtl;
}

assert_lint_ok "multiline-signal-declaration" {
library ieee;
use ieee.std_logic_1164.all;

entity multiline_signal is
end multiline_signal;

architecture rtl of multiline_signal is
    signal wrapped :
        std_logic_vector
        (
            7 downto 0
        )
        := (others => '0');
begin
end rtl;
}

assert_lint_ok "character-literal-parenthesis" {
library ieee;
use ieee.std_logic_1164.all;

entity char_literal_paren is
end char_literal_paren;

architecture rtl of char_literal_paren is
    constant LPAREN : character := '(';
begin
end rtl;
}

assert_lint_error "duplicate-port-after-vector" {
library ieee;
use ieee.std_logic_1164.all;

entity duplicate_after_vector is
    port (
        data : in std_logic_vector(7 downto 0);
        data : out std_logic
    );
end duplicate_after_vector;

architecture rtl of duplicate_after_vector is
begin
end rtl;
} "duplicate port name"

assert_lint_error "truthy-lint-value" {
library ieee;
use ieee.std_logic_1164.all;

entity truthy_lint is
    po
rt (
        clk : in std_logic
    );
end truthy_lint;
} "keyword port cannot be split" 1

assert_lint_keeps_string_comment_marker "doubled-quote-string-comment-marker" {
library ieee;
use ieee.std_logic_1164.all;

entity doubled_quote_string is
end doubled_quote_string;

architecture rtl of doubled_quote_string is
    constant MSG : string := "quoted "" -- not a comment "" text";
begin
end rtl;
} "not a comment"

puts ""
puts "=========================================="
puts "Test Summary"
puts "=========================================="
puts "Total:  $total"
puts "Passed: $passed"
puts "Failed: $failed"

if {$failed > 0} {
    exit 1
}
exit 0
