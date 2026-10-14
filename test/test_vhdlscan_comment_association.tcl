#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# One comment-association rule for every declaration kind (#31, #36, #37).
#
# The comment attached to a function, procedure, process, instantiation,
# signal, constant or type is the contiguous block of full-line comments
# directly above it (ended by a blank line or a code line), then the trailing
# comment on its own line, joined with newlines. @brief is kept verbatim and
# does not decide whether a comment attaches.
#
# The table applies six placements to the seven kinds:
#   a  a comment directly above
#   b  a trailing comment on the declaration's line
#   c  only the previous declaration's trailing comment on the line above
#   d  a block of three comment lines directly above
#   e  a comment above, separated by a blank line
#   f  a `--! @brief` comment directly above
# Cells are 10 blank lines apart, so no cell can reach another. Further rows
# cover #36's example, a dense layout without cross-talk, split headers (the
# block and the trailing comment both anchor on the keyword line), a trailing
# comment on an `end ...;` line, the package, package body and process-local
# contexts, and the public comments output.

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set ::pass_count 0
set ::fail_count 0
set ::tmp_files {}
set ::tmp_dir ""

# Equality assertion that prints the observed value on failure, so a run on an
# unpatched tree documents what it returned.
proc check_eq {label got expected} {
    if {$got eq $expected} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        set g [string map {\n {\n}} $got]
        set x [string map {\n {\n}} $expected]
        puts "FAIL: $label (expected \"$x\", got \"$g\")"
        incr ::fail_count
    }
}

# Fixtures are written to a unique per-run directory under the system temp
# directory (TMPDIR, TEMP or TMP; else /tmp; else the current directory) and
# removed in a finally block.
proc make_tmp_dir {} {
    set base ""
    foreach var {TMPDIR TEMP TMP} {
        if {[info exists ::env($var)] && [file isdirectory $::env($var)]} {
            set base $::env($var)
            break
        }
    }
    if {$base eq ""} {
        set base [expr {[file isdirectory /tmp] ? "/tmp" : [pwd]}]
    }
    set dir [file join $base "aurig_core_comment_association_[pid]_[clock milliseconds]"]
    file mkdir $dir
    return $dir
}

# Write a fixture from a list of lines (LF, binary mode: no translation).
proc tmp_vhd_lines {basename lines} {
    set path [file join $::tmp_dir "${basename}.vhd"]
    lappend ::tmp_files $path
    set fp [open $path w]
    try {
        fconfigure $fp -translation binary
        puts -nonewline $fp "[join $lines \n]\n"
    } finally {
        close $fp
    }
    return $path
}

proc cleanup_tmp_files {} {
    foreach path $::tmp_files {
        catch {file delete -- $path}
    }
    if {$::tmp_dir ne ""} {
        catch {file delete -force -- $::tmp_dir}
    }
}

proc parse {path} {
    return [::aurig::core::analyze::vhdlscan -in $path -verbosity 0]
}

# Comment of the record named $name in $records (by `name` or `label`):
# "<none>" without a comment, "<missing>" without such a record.
proc comment_of {records name} {
    foreach r $records {
        set n [expr {[dict exists $r name] ? [dict get $r name] : [dict get $r label]}]
        if {$n eq $name} {
            return [expr {[dict exists $r comment] ? [dict get $r comment] : "<none>"}]
        }
    }
    return "<missing>"
}

# Every record of the architecture of entity $ent: declarations, processes,
# instantiations and the declarations inside processes.
proc arch_records {parsed ent} {
    set out {}
    foreach a [dict get $parsed architectures] {
        if {[dict get $a entity] ne $ent} { continue }
        lappend out {*}[dict get $a declarations]
        foreach p [dict get $a processes] {
            lappend out $p
            if {[dict exists $p declarations]} {
                lappend out {*}[dict get $p declarations]
            }
        }
        lappend out {*}[dict get $a instantiations]
    }
    return $out
}

proc package_records {parsed} {
    set out {}
    foreach p [dict get $parsed packages] {
        lappend out {*}[dict get $p declarations]
    }
    foreach b [dict get $parsed package_bodies] {
        lappend out {*}[dict get $b functions] {*}[dict get $b procedures]
    }
    return $out
}

# --- Fixture builder ------------------------------------------------------------
set ::src {}
proc L {args} {
    foreach text $args { lappend ::src $text }
}
proc gap {} {
    for {set i 0} {$i < 10} {incr i} { L {} }
}

# One declaration of $kind named $name; $tail is appended to its first line.
# Single-line kinds put the trailing comment of cell c on that line; the
# multi-line kinds (function, procedure, process) end on an `end ...;` line.
proc decl_lines {kind name tail} {
    switch -- $kind {
        function  { return [list "  function ${name}(x : integer) return integer is$tail" \
                        {  begin} {    return x;} {  end function;}] }
        procedure { return [list "  procedure ${name}(x : integer) is$tail" \
                        {  begin} {    null;} {  end procedure;}] }
        process   { return [list "  $name : process (clk)$tail" {  begin} {  end process;}] }
        instantiation { return [list "  $name : entity work.leaf port map (clk => clk);$tail"] }
        signal    { return [list "  signal $name : std_logic;$tail"] }
        constant  { return [list "  constant $name : integer := 1;$tail"] }
        type      { return [list "  type $name is (V0_$name, V1_$name);$tail"] }
    }
}

set prefix [dict create function f procedure p process proc instantiation u \
    signal s constant C type t]

# Emit the six cells of $kind. Returns {cell name ...}.
proc emit_cells {kind} {
    set pf [dict get $::prefix $kind]
    set names [dict create]
    foreach cell {a b c d e f} {
        set n "${pf}_$cell"
        set tail ""
        gap
        switch -- $cell {
            a { L "  -- $kind a above" }
            b { set tail " -- $kind b trailing" }
            c {
                set prev [decl_lines $kind ${pf}_cprev ""]
                lset prev end "[lindex $prev end] -- $kind c trailing of prev"
                L {*}$prev
                dict set names cprev ${pf}_cprev
            }
            d { L "  -- $kind d block line 1" "  -- $kind d block line 2" "  -- $kind d block line 3" }
            e { L "  -- $kind e above blank" {} }
            f { L "  --! @brief $kind f brief" }
        }
        L {*}[decl_lines $kind $n $tail]
        dict set names $cell $n
    }
    return $names
}

set ::tmp_dir [make_tmp_dir]
try {
    # --- The table --------------------------------------------------------------
    set ::src {}
    L {library ieee;} {use ieee.std_logic_1164.all;} {}
    L {entity leaf is} {  port (clk : in std_logic);} {end entity leaf;}
    L {architecture rtl of leaf is} {begin} {  assert true;} {end architecture rtl;} {}
    L {entity tbl is} {  port (clk : in std_logic);} {end entity tbl;} {}
    L {architecture rtl of tbl is}
    set cells [dict create]
    foreach kind {function procedure signal constant type} {
        dict set cells $kind [emit_cells $kind]
    }
    gap
    L {begin}
    foreach kind {process instantiation} {
        dict set cells $kind [emit_cells $kind]
    }
    L {} {end architecture rtl;}
    set recs [arch_records [parse [tmp_vhd_lines table $::src]] tbl]

    foreach kind {function procedure process instantiation signal constant type} {
        set names [dict get $cells $kind]
        check_eq "table $kind a: comment directly above" \
            [comment_of $recs [dict get $names a]] "$kind a above"
        check_eq "table $kind b: trailing comment" \
            [comment_of $recs [dict get $names b]] "$kind b trailing"
        check_eq "table $kind c: previous declaration's trailing comment is not taken" \
            [comment_of $recs [dict get $names c]] "<none>"
        check_eq "table $kind d: block of three lines" \
            [comment_of $recs [dict get $names d]] \
            "$kind d block line 1\n$kind d block line 2\n$kind d block line 3"
        check_eq "table $kind e: comment above a blank line is not attached" \
            [comment_of $recs [dict get $names e]] "<none>"
        check_eq "table $kind f: @brief kept verbatim" \
            [comment_of $recs [dict get $names f]] "@brief $kind f brief"
    }

    # A trailing comment on an `end ...;` line attaches to nothing: not to the
    # declaration it closes (that is not its declaration line), not to the
    # next one (it ends the block above).
    foreach kind {function procedure process} {
        check_eq "end-line trailing comment: $kind before it gets nothing" \
            [comment_of $recs [dict get $cells $kind cprev]] "<none>"
    }
    # A single-line declaration keeps its own trailing comment.
    foreach kind {instantiation signal constant type} {
        check_eq "own trailing comment: $kind keeps it" \
            [comment_of $recs [dict get $cells $kind cprev]] "$kind c trailing of prev"
    }

    # --- #36: the block above stops at a line holding code ----------------------
    set ::src {}
    L {package p36 is}
    L {  procedure a(x : integer); -- Trailing for a}
    L {  -- Comment for b}
    L {  procedure b(x : integer);}
    L {}
    L {  function fa(x : integer) return integer; -- Trailing for fa}
    L {  -- Comment for fb}
    L {  function fb(x : integer) return integer;}
    L {}
    L {  function ga(x : integer) return integer; -- Trailing for ga}
    L {  --! @brief Comment for gb}
    L {  function gb(x : integer) return integer;}
    L {end package p36;}
    set recs [package_records [parse [tmp_vhd_lines i36 $::src]]]
    check_eq "#36 procedure a keeps its trailing comment" [comment_of $recs a] "Trailing for a"
    check_eq "#36 procedure b gets only its own comment" [comment_of $recs b] "Comment for b"
    check_eq "#36 function fa keeps its trailing comment" [comment_of $recs fa] "Trailing for fa"
    check_eq "#36 function fb gets only its own comment" [comment_of $recs fb] "Comment for fb"
    check_eq "#36 function gb gets only its own @brief comment" [comment_of $recs gb] "@brief Comment for gb"

    # --- Dense layout: no cross-talk between neighbours -------------------------
    set ::src {}
    L {library ieee;} {use ieee.std_logic_1164.all;} {}
    L {entity leaf is} {  port (clk : in std_logic);} {end entity leaf;}
    L {architecture rtl of leaf is} {begin} {  assert true;} {end architecture rtl;} {}
    L {entity dense is} {  port (clk : in std_logic);} {end entity dense;} {}
    L {architecture rtl of dense is}
    L {  -- Signals}
    L {  signal s_one : std_logic;}
    L {  signal s_two : std_logic;}
    L {}
    L {  -- First constant}
    L {  constant C_ONE : integer := 1;}
    L {  constant C_TWO : integer := 2;}
    L {  -- A type}
    L {  type t_one is (T0, T1);}
    L {  type t_two is (T2, T3);}
    L {begin}
    L {  -- First instance}
    L {  u_one : entity work.leaf port map (clk => clk);}
    L {  u_two : entity work.leaf port map (clk => clk);}
    L {}
    L {  -- First process}
    L {  p_one : process (clk)}
    L {  begin}
    L {  end process;}
    L {  p_two : process (clk)}
    L {  begin}
    L {  end process;}
    L {end architecture rtl;}
    set recs [arch_records [parse [tmp_vhd_lines dense $::src]] dense]
    check_eq "dense: s_one takes the heading above it" [comment_of $recs s_one] "Signals"
    check_eq "dense: s_two takes nothing" [comment_of $recs s_two] "<none>"
    check_eq "dense: C_ONE takes its own comment" [comment_of $recs C_ONE] "First constant"
    check_eq "dense: C_TWO takes nothing" [comment_of $recs C_TWO] "<none>"
    check_eq "dense: t_one takes its own comment" [comment_of $recs t_one] "A type"
    check_eq "dense: t_two takes nothing" [comment_of $recs t_two] "<none>"
    check_eq "dense: u_one takes its own comment" [comment_of $recs u_one] "First instance"
    check_eq "dense: u_two takes nothing" [comment_of $recs u_two] "<none>"
    check_eq "dense: p_one takes its own comment" [comment_of $recs p_one] "First process"
    check_eq "dense: p_two takes nothing" [comment_of $recs p_two] "<none>"

    # --- Split headers: the block and the trailing comment anchor on the keyword line
    set ::src {}
    L {package psplit is}
    L {  -- Split constant}
    L {  constant}
    L {    C_SPLIT : integer := 1;}
    L {}
    L {  -- Split function}
    L {  function}
    L {    f_split(x : integer) return integer;}
    L {}
    L {  -- Split type}
    L {  type}
    L {    t_split is (S0, S1);}
    L {}
    L {  function -- On the keyword line}
    L {    f_kw(x : integer) return integer;}
    L {}
    L {  function}
    L {    f_name(x : integer) return integer; -- On the name line}
    L {end package psplit;}
    set recs [package_records [parse [tmp_vhd_lines split $::src]]]
    check_eq "split header: constant" [comment_of $recs C_SPLIT] "Split constant"
    check_eq "split header: function" [comment_of $recs f_split] "Split function"
    check_eq "split header: type" [comment_of $recs t_split] "Split type"
    # The trailing comment anchors on the keyword line too: a comment there
    # attaches, a comment on the name line alone does not.
    check_eq "split header: trailing comment on the keyword line attaches" \
        [comment_of $recs f_kw] "On the keyword line"
    check_eq "split header: trailing comment on the name line does not attach" \
        [comment_of $recs f_name] "<none>"

    # --- Contexts: package, package body, process-local -------------------------
    set ::src {}
    L {library ieee;} {use ieee.std_logic_1164.all;} {}
    L {package pctx is}
    L {  -- Package constant}
    L {  constant C_PKG : integer := 1;}
    L {  type t_pkg is (P0, P1); -- Package type}
    L {  -- Package function}
    L {  function f_pkg(x : integer) return integer;}
    L {  procedure p_pkg(x : integer); -- Package procedure}
    L {end package pctx;}
    L {}
    L {package body pctx is}
    L {  -- Body function}
    L {  function f_pkg(x : integer) return integer is}
    L {  begin}
    L {    return x;}
    L {  end function;}
    L {}
    L {  procedure p_pkg(x : integer) is -- Body procedure}
    L {  begin}
    L {    null;}
    L {  end procedure;}
    L {end package body pctx;}
    L {}
    L {entity ctx is} {  port (clk : in std_logic);} {end entity ctx;} {}
    L {architecture rtl of ctx is}
    L {  signal s_ctx : std_logic;}
    L {begin}
    L {  main : process (clk) is}
    L {    -- Local type}
    L {    type t_local is (L0, L1);}
    L {    -- Local function}
    L {    function f_local(x : integer) return integer is}
    L {    begin}
    L {      return x;}
    L {    end function;}
    L {    procedure p_local(x : integer) is -- Local procedure}
    L {    begin}
    L {      null;}
    L {    end procedure;}
    L {  begin}
    L {  end process main;}
    L {end architecture rtl;}
    set parsed [parse [tmp_vhd_lines contexts $::src]]
    set pkg [dict get [lindex [dict get $parsed packages] 0] declarations]
    set body [lindex [dict get $parsed package_bodies] 0]
    set local [arch_records $parsed ctx]
    check_eq "package: constant" [comment_of $pkg C_PKG] "Package constant"
    check_eq "package: type" [comment_of $pkg t_pkg] "Package type"
    check_eq "package: function" [comment_of $pkg f_pkg] "Package function"
    check_eq "package: procedure" [comment_of $pkg p_pkg] "Package procedure"
    check_eq "package body: function" [comment_of [dict get $body functions] f_pkg] "Body function"
    check_eq "package body: procedure" [comment_of [dict get $body procedures] p_pkg] "Body procedure"
    check_eq "process-local: type" [comment_of $local t_local] "Local type"
    check_eq "process-local: function" [comment_of $local f_local] "Local function"
    check_eq "process-local: procedure" [comment_of $local p_local] "Local procedure"

    # --- Public comments output keeps its shape ---------------------------------
    # The trailing flag used for association is internal: every entry still
    # carries only `comment`, full-line and trailing alike.
    set ::src {}
    L {entity pub is}
    L {  port (clk : in bit); -- trailing on code}
    L {end entity pub;}
    L {-- full-line}
    L {architecture rtl of pub is}
    L {  signal s : bit; -- after a signal}
    L {begin}
    L {  s <= clk;}
    L {end architecture rtl;}
    set parsed [parse [tmp_vhd_lines public $::src]]
    check_eq "public comments output is unchanged in shape" [dict get $parsed comments] \
        {line {2 {comment {trailing on code}} 4 {comment full-line} 6 {comment {after a signal}}}}
} finally {
    cleanup_tmp_files
}

puts ""
puts "Passed: $::pass_count"
puts "Failed: $::fail_count"
exit [expr {$::fail_count > 0}]
