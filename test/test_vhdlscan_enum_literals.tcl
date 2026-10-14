# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Feature (#26): an enumerated type declaration must return its literals,
# each with its verbatim name, its kind (identifier / character) and its own
# absolute physical line, at the SAME top-level key path in a package and in
# an architecture declarative part.
#
# Background: _scan_architecture_types already hands the literal list to
# _grab_paren_block to find the closing ')', then throws the parsed content
# away, so only `subtype_kind enumerated` ever reached the caller. On top of
# that, add_decl nests every extra field under `args` while add_decl_pkg
# keeps them top-level, so the same declaration read out at two different
# key paths depending on context.
#
# The assertions below read the literals at the top level ONLY — they never
# fall back to the `args` copy — so an architecture declaration that
# publishes the field under `args` alone counts as missing it.
#
# Every fixture is written with explicit line endings so the asserted line
# numbers are the physical lines of the file.
#=============================================================================

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core

set ::pass_count 0
set ::fail_count 0
set ::tmp_files {}
set ::tmp_dir ""

proc check {label cond} {
    if {[uplevel 1 [list expr $cond]]} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label"
        incr ::fail_count
    }
}

# Equality assertion that prints the observed value on failure, so a run on
# an unpatched tree documents what the parser actually returned.
proc check_eq {label got expected} {
    if {$got eq $expected} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (expected {$expected}, got {$got})"
        incr ::fail_count
    }
}

# Presence assertion for a key read at the top level of a declaration record.
proc check_has {label decl key} {
    if {[dict exists $decl $key]} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (no top-level `$key` in {$decl})"
        incr ::fail_count
    }
}

proc check_lacks {label decl key} {
    if {![dict exists $decl $key]} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label (unexpected `$key` = {[dict get $decl $key]})"
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
    set dir [file join $base "aurig_core_enum_literals_[pid]_[clock milliseconds]"]
    file mkdir $dir
    return $dir
}

# Write a fixture from a list of lines with the requested line ending.
# eol: lf | crlf. The file is written in binary mode so no translation
# happens on any platform. The path is registered for cleanup BEFORE the
# file is created, and the channel is closed in a finally clause, so an
# error during the write cannot leak either.
proc tmp_vhd_lines {basename lines {eol lf}} {
    set path [file join $::tmp_dir "${basename}.vhd"]
    lappend ::tmp_files $path
    set sep [expr {$eol eq "crlf" ? "\r\n" : "\n"}]
    set fp [open $path w]
    try {
        fconfigure $fp -translation binary
        puts -nonewline $fp "[join $lines $sep]$sep"
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

# Return the first item named $name in $items, or {} if there is none.
proc find_named {items name} {
    foreach item $items {
        if {[dict exists $item name] && [dict get $item name] eq $name} { return $item }
    }
    return {}
}

# Declaration $name in the first package declaration.
proc pkg_decl {parsed name} {
    set pkg [lindex [dict get $parsed packages] 0]
    return [find_named [dict get $pkg declarations] $name]
}

# Declaration $name in the first architecture.
proc arch_decl {parsed name} {
    set arch [lindex [dict get $parsed architectures] 0]
    return [find_named [dict get $arch declarations] $name]
}

# Literal projections. They read `literals` at the top level only and return
# an empty list when it is absent, so an unpatched tree fails the assertion
# with an empty observed value instead of erroring out.
proc lit_field {decl field} {
    set out {}
    if {![dict exists $decl literals]} { return $out }
    foreach lit [dict get $decl literals] {
        lappend out [expr {[dict exists $lit $field] ? [dict get $lit $field] : "<missing>"}]
    }
    return $out
}
proc lit_names {decl} { return [lit_field $decl name] }
proc lit_kinds {decl} { return [lit_field $decl kind] }
proc lit_lines {decl} { return [lit_field $decl line] }

set ::tmp_dir [make_tmp_dir]

try {

# ----------------------------------------------------------------------------
# Fixture A — enumerated types in a package declaration, in every spelling
# the scanner has to cope with. Line numbers are the physical lines below.
# ----------------------------------------------------------------------------
set parsed_a [parse [tmp_vhd_lines "enum_pkg" {
    {package p is}
    {    type simple_t is (IDLE, RUN, DONE);}
    {    type split_t is (}
    {        NORTH,}
    {        SOUTH,}
    {        EAST}
    {    );}
    {    type commented_t is (}
    {        RED,    -- primary}
    {        GREEN,  -- primary}
    {        -- a standalone comment line}
    {        BLUE}
    {    );}
    {    type charlit_t is ('0', '1', 'X');}
    {    type mixed_t is ('0', LOW, 'X', HIGH);}
    {    type punct_t is (',', '(', ')');}
    {    type after_punct_t is (TAIL_A, TAIL_B);}
    {    type esc_t is (\weird_name\, NORMAL);}
    {    type esc_comma_t is (\a,b\, C);}
    {end package p;}
}]]

# -- N1: the literals are returned at all.
check_has "N1 package enum carries a top-level `literals` key" \
    [pkg_decl $parsed_a simple_t] literals

# -- N2: one entry per literal.
check_eq "N2 (IDLE, RUN, DONE) yields three literals" \
    [llength [lit_names [pkg_decl $parsed_a simple_t]]] 3
check_eq "N2 literal names are verbatim and in source order" \
    [lit_names [pkg_decl $parsed_a simple_t]] {IDLE RUN DONE}
check_eq "N2 single-line enum: every literal on the declaration's line" \
    [lit_lines [pkg_decl $parsed_a simple_t]] {2 2 2}

# -- N3: a list split over several lines reports each literal's own line.
check_eq "N3 split enum names" \
    [lit_names [pkg_decl $parsed_a split_t]] {NORTH SOUTH EAST}
check_eq "N3 split enum lines are 4, 5, 6" \
    [lit_lines [pkg_decl $parsed_a split_t]] {4 5 6}

# -- N4: comments between literals cost a line but never shift one. BLUE sits
# on line 12; line 11 is the standalone comment.
check_eq "N4 comment-interleaved enum names" \
    [lit_names [pkg_decl $parsed_a commented_t]] {RED GREEN BLUE}
check_eq "N4 comment-interleaved enum lines are 9, 10, 12 (not 9, 10, 11)" \
    [lit_lines [pkg_decl $parsed_a commented_t]] {9 10 12}

# -- N5: character literals keep their quotes and are classified as such.
check_eq "N5 character literal names keep their quotes" \
    [lit_names [pkg_decl $parsed_a charlit_t]] {'0' '1' 'X'}
check_eq "N5 character literals are kind=character" \
    [lit_kinds [pkg_decl $parsed_a charlit_t]] {character character character}
check_eq "N5 character literals report the declaration's line" \
    [lit_lines [pkg_decl $parsed_a charlit_t]] {14 14 14}

# -- N6: a mixed list classifies each literal independently.
check_eq "N6 mixed enum names" \
    [lit_names [pkg_decl $parsed_a mixed_t]] {'0' LOW 'X' HIGH}
check_eq "N6 mixed enum kinds alternate correctly" \
    [lit_kinds [pkg_decl $parsed_a mixed_t]] {character identifier character identifier}

# -- N6b: an extended identifier is kept verbatim and classified as an
# identifier.
# Compared element by element: the canonical Tcl list representation of a
# backslash-bearing element escapes those backslashes, so comparing the
# whole list would test Tcl's quoting rather than the literal's text.
check_eq "N6b extended identifier kept verbatim" \
    [lindex [lit_names [pkg_decl $parsed_a esc_t]] 0] "\\weird_name\\"
check_eq "N6b plain identifier following an extended one" \
    [lindex [lit_names [pkg_decl $parsed_a esc_t]] 1] "NORMAL"
check_eq "N6b extended identifier is kind=identifier" \
    [lit_kinds [pkg_decl $parsed_a esc_t]] {identifier identifier}

# The walker consumes an extended identifier through to its closing
# backslash, so a comma inside one does not end the literal. This is the one
# case where the dedicated walker and the general splitter it replaces
# disagree: `_split_top_level_commas` cuts the same text into three parts,
# splitting the extended identifier down the middle. Pinned here so a later
# "simplification" back onto the shared splitter cannot silently start
# emitting bogus literals.
check_eq "N6b comma inside an extended identifier does not split it" \
    [llength [lit_names [pkg_decl $parsed_a esc_comma_t]]] 2
check_eq "N6b extended identifier containing a comma kept whole" \
    [lindex [lit_names [pkg_decl $parsed_a esc_comma_t]] 0] "\\a,b\\"
check_eq "N6b literal following an extended identifier containing a comma" \
    [lindex [lit_names [pkg_decl $parsed_a esc_comma_t]] 1] "C"

# -- N7: punctuation character literals must not desync the paren matcher.
check_eq "N7 punctuation character literals" \
    [lit_names [pkg_decl $parsed_a punct_t]] {',' '(' ')'}
check_eq "N7 punctuation character literals are kind=character" \
    [lit_kinds [pkg_decl $parsed_a punct_t]] {character character character}
check_eq "N7 the declaration after the punctuation enum still parses" \
    [lit_names [pkg_decl $parsed_a after_punct_t]] {TAIL_A TAIL_B}

# ----------------------------------------------------------------------------
# Fixture B — the same enumerated type declared in a package and in an
# architecture declarative part. This is the #25 half of the change: both
# records must expose `subtype_kind` and `literals` at the same key path.
# ----------------------------------------------------------------------------
set parsed_b [parse [tmp_vhd_lines "enum_both_contexts" {
    {package pkg_ctx is}
    {    type state_t is (IDLE, RUN, DONE);}
    {end package pkg_ctx;}
    {}
    {entity e is}
    {end entity e;}
    {}
    {architecture rtl of e is}
    {    type state_t is (IDLE, RUN, DONE);}
    {    signal s : state_t := IDLE;}
    {begin}
    {    s <= RUN;}
    {end architecture rtl;}
}]]

set pkg_state  [pkg_decl  $parsed_b state_t]
set arch_state [arch_decl $parsed_b state_t]

# -- N8: same key path in both contexts.
check_has "N8 architecture enum carries a top-level `subtype_kind`" \
    $arch_state subtype_kind
check_has "N8 architecture enum carries a top-level `literals`" \
    $arch_state literals
check_eq "N8 subtype_kind agrees between package and architecture" \
    [expr {[dict exists $arch_state subtype_kind] ? [dict get $arch_state subtype_kind] : "<missing>"}] \
    [expr {[dict exists $pkg_state subtype_kind] ? [dict get $pkg_state subtype_kind] : "<missing>"}]
# Compared against the expected list rather than against each other: two
# absent `literals` keys agree with one another vacuously, which would let
# these two assertions pass on an unpatched tree and test nothing.
check_eq "N8 package literal names" \
    [lit_names $pkg_state] {IDLE RUN DONE}
check_eq "N8 architecture literal names (same value, same key path)" \
    [lit_names $arch_state] {IDLE RUN DONE}
check_eq "N8 package literal kinds" \
    [lit_kinds $pkg_state] {identifier identifier identifier}
check_eq "N8 architecture literal kinds (same value, same key path)" \
    [lit_kinds $arch_state] {identifier identifier identifier}
check_eq "N8 package literals report line 2" \
    [lit_lines $pkg_state] {2 2 2}
check_eq "N8 architecture literals report line 9" \
    [lit_lines $arch_state] {9 9 9}

# ----------------------------------------------------------------------------
# Fixture C — non-enumerated type forms and a subtype. Positive control
# against over-emission: these must carry no `literals` at all, and their
# existing `subtype_kind` must be untouched. Both already hold on main.
# ----------------------------------------------------------------------------
set parsed_c [parse [tmp_vhd_lines "non_enum_pkg" {
    {package n is}
    {    type count_t is range 0 to 15;}
    {    type bytes_t is array (0 to 3) of integer;}
    {    type rec_t is record}
    {        a : integer;}
    {        b : integer;}
    {    end record;}
    {    type dist_t is range 0 to 1000000}
    {        units}
    {            um;}
    {            mm = 1000 um;}
    {        end units;}
    {    subtype small_t is integer range 0 to 7;}
    {end package n;}
}]]

# -- N9: no literals on anything that is not an enumeration.
foreach {name kindname} {count_t integer_range bytes_t array rec_t record dist_t physical} {
    check_lacks "N9 $kindname type carries no `literals`" [pkg_decl $parsed_c $name] literals
    check_eq "N9 $kindname type keeps subtype_kind=$kindname" \
        [expr {[dict exists [pkg_decl $parsed_c $name] subtype_kind] ?
               [dict get [pkg_decl $parsed_c $name] subtype_kind] : "<missing>"}] $kindname
}
check_lacks "N9 subtype carries no `literals`" [pkg_decl $parsed_c small_t] literals
check_lacks "N9 subtype carries no `subtype_kind`" [pkg_decl $parsed_c small_t] subtype_kind

# ----------------------------------------------------------------------------
# N10 — regression guard: kind, name and line of the type declarations
# themselves are unchanged. All of these already hold on main.
# ----------------------------------------------------------------------------
foreach {name line} {simple_t 2 split_t 3 commented_t 8 charlit_t 14 mixed_t 15 punct_t 16} {
    set d [pkg_decl $parsed_a $name]
    check_eq "N10 $name kind is `type`" [dict get $d kind] type
    check_eq "N10 $name name is unchanged" [dict get $d name] $name
    check_eq "N10 $name line is $line" [dict get $d line] $line
    check_eq "N10 $name subtype_kind is enumerated" \
        [expr {[dict exists $d subtype_kind] ? [dict get $d subtype_kind] : "<missing>"}] enumerated
}
check_eq "N10 architecture type declaration keeps kind/name/line" \
    [list [dict get $arch_state kind] [dict get $arch_state name] [dict get $arch_state line]] \
    {type state_t 9}

} finally {
    cleanup_tmp_files
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "test_vhdlscan_enum_literals.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
