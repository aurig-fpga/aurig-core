# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Focused regression tests for large VHDL declarative sections.

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set build_dir [file join $aurig_core_root "test" "build" "vhdlscan_large_declarations"]
file delete -force $build_dir
file mkdir $build_dir

set failures 0

proc assert_true {condition message} {
    global failures
    if {[uplevel 1 [list expr $condition]]} {
        puts "PASS: $message"
    } else {
        puts "FAIL: $message"
        incr failures
    }
}

proc capture_stdout {script output_var} {
    upvar 1 $output_var output
    set output ""
    set ::__vhdlscan_capture_buffer ""
    rename ::puts ::__vhdlscan_capture_orig_puts
    proc ::puts {args} {
        set nonewline 0
        set channel stdout
        set idx 0
        if {[llength $args] > 0 && [lindex $args 0] eq "-nonewline"} {
            set nonewline 1
            incr idx
        }
        set remaining [expr {[llength $args] - $idx}]
        if {$remaining == 1} {
            set text [lindex $args $idx]
        } elseif {$remaining == 2} {
            set channel [lindex $args $idx]
            incr idx
            set text [lindex $args $idx]
        } else {
            return -code error {wrong # args: should be "puts ?-nonewline? ?channelId? string"}
        }
        if {$channel eq "stdout"} {
            append ::__vhdlscan_capture_buffer $text
            if {!$nonewline} {
                append ::__vhdlscan_capture_buffer "\n"
            }
        } else {
            ::__vhdlscan_capture_orig_puts {*}$args
        }
    }

    set code [catch {uplevel 1 $script} result opts]
    set output $::__vhdlscan_capture_buffer
    rename ::puts {}
    rename ::__vhdlscan_capture_orig_puts ::puts
    unset ::__vhdlscan_capture_buffer
    return -options $opts $result
}

proc write_large_lut_fixture {path entries} {
    set fh [open $path w]
    fconfigure $fh -translation lf -encoding utf-8
    puts $fh {library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity large_lut is
    port (
        clk_i  : in std_logic;
        addr_i : in std_logic_vector(12 downto 0);
        data_o : out std_logic_vector(13 downto 0)
    );
end entity large_lut;

architecture rtl of large_lut is
    type ram_type is array (0 to 8191) of std_logic_vector(13 downto 0);
    signal s_addr : std_logic_vector(12 downto 0);
    signal s_data : std_logic_vector(13 downto 0);
    constant C_LUT : ram_type := (}
    for {set i 0} {$i < $entries} {incr i} {
        set comma [expr {$i + 1 < $entries ? "," : ""}]
        puts $fh "        std_logic_vector(to_unsigned([expr {$i % 16384}],14))$comma -- generated LUT value"
    }
    puts $fh {    );
begin
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            s_addr <= addr_i;
            s_data <= C_LUT(to_integer(unsigned(s_addr)));
            data_o <= s_data;
        end if;
    end process;
end architecture rtl;
}
    close $fh
}

proc write_package_body_fixture {path} {
    set fh [open $path w]
    fconfigure $fh -translation lf -encoding utf-8
    puts -nonewline $fh {package package_body_quiet is
    function f_id(inp : integer) return integer;
end package;

package body package_body_quiet is
    function f_id(inp : integer) return integer is
    begin
        return inp;
    end function;
end package body;
}
    close $fh
}

set fixture [file join $build_dir large_lut.vhd]
write_large_lut_fixture $fixture 8192

set start_ms [clock milliseconds]
if {[catch {set parsed [::aurig::core::analyze::vhdlscan -in $fixture -verbosity 0]} err]} {
    puts "FAIL: vhdlscan parses large LUT fixture"
    puts "      $err"
    incr failures
} else {
    set elapsed_ms [expr {[clock milliseconds] - $start_ms}]
    puts "INFO: large LUT parse elapsed ${elapsed_ms}ms"
    assert_true {$elapsed_ms < 15000} "vhdlscan avoids regex backtracking on large constant declarations"
    assert_true {[dict exists $parsed architectures] && [llength [dict get $parsed architectures]] == 1} \
        "vhdlscan records the large LUT architecture"
    set declarations [dict get [lindex [dict get $parsed architectures] 0] declarations]
    set seen {}
    foreach decl $declarations {
        dict set seen "[dict get $decl kind]:[dict get $decl name]" 1
    }
    assert_true {[dict exists $seen "signal:s_addr"] && [dict exists $seen "signal:s_data"]} \
        "vhdlscan keeps signal declarations before the large constant"
    assert_true {[dict exists $seen "constant:C_LUT"]} \
        "vhdlscan keeps the large constant declaration"
}

set package_fixture [file join $build_dir package_body_quiet.vhd]
write_package_body_fixture $package_fixture

if {[catch {
    capture_stdout {
        set package_result [::aurig::core::analyze::vhdlscan -in $package_fixture -verbosity 0]
    } package_stdout
} err]} {
    puts "FAIL: vhdlscan parses package-body fixture"
    puts "      $err"
    incr failures
} else {
    assert_true {$package_stdout eq ""} "vhdlscan -verbosity 0 suppresses package body debug output"
    assert_true {[dict exists $package_result package_body]} "vhdlscan records package body content"
}

if {$failures > 0} {
    puts "FAILURES: $failures"
    exit 1
}

puts "PASS: test_vhdlscan_large_declarations.tcl"
