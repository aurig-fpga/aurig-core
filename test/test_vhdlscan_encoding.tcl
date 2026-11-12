# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Issue #81: UTF-8 input must not depend on the system encoding. Malformed
# UTF-8 falls back to cp1252 for the whole file, after one initial BOM.
set core_root [file dirname [file dirname [file normalize [info script]]]]
lappend ::auto_path $core_root
package require aurig::core

set passed 0
set failed 0
proc check_eq {label actual expected} {
    if {$actual eq $expected} {
        incr ::passed
        puts "PASS: $label"
    } else {
        incr ::failed
        puts "FAIL: $label (expected [list $expected], got [list $actual])"
    }
}

proc with_system_encoding {name script} {
    set previous [encoding system]
    try {
        encoding system $name
        uplevel 1 $script
    } finally {
        encoding system $previous
    }
}

proc capture_lint_content {command operation} {
    set ::lint_content [lindex $command 1]
}

set temp_base [pwd]
foreach name {TMPDIR TEMP TMP} {
    if {[info exists ::env($name)] && [file isdirectory $::env($name)]} {
        set temp_base $::env($name)
        break
    }
}
if {$temp_base eq [pwd] && [file isdirectory /tmp]} {set temp_base /tmp}
set temp_dir [file join $temp_base "aurig_core_encoding_[pid]_[clock clicks]"]
file mkdir $temp_dir
set cases {}
set body "entity Dut is\nend entity Dut;\n"
set bom [binary format H* efbbbf]

proc add_case {name bytes text line {comment ""} {entities Dut} {comment_line ""}} {
    set path [file join $::temp_dir "${name}.vhd"]
    set fp [open $path wb]
    try {
        puts -nonewline $fp $bytes
    } finally {
        close $fp
    }
    lappend ::cases [list $name $path $text $line $comment $entities $comment_line]
}

proc add_comment_case {name hex expected} {
    # Surround the payload so whitespace/control characters are not trimmed
    # from the expected comment. Expected text is independent of the decoder.
    set bytes "-- A[binary format H* $hex]Z\n$::body"
    add_case $name $bytes "-- A${expected}Z\n$::body" 2 "A${expected}Z"
}

set original_encoding [encoding system]
trace add execution ::aurig::core::analyze::_validate_vhdl_lint_syntax enter capture_lint_content
try {
    add_case plain $body $body 1
    add_case bom_entity "$bom$body" $body 1
    add_case bom_comment "$bom-- heading\n$body" "-- heading\n$body" 2 heading
    add_case double_bom "$bom$bom$body" "\ufeff$body" 1
    # The tolerant parser returns an empty AST for input with no design units.
    add_case empty "" "" 0 "" {}
    add_case bom_only $bom "" 0 "" {}
    set no_final_newline [string trimright $body \n]
    add_case no_final_newline $no_final_newline $no_final_newline 1
    add_case bom_no_final_newline "$bom$no_final_newline" $no_final_newline 1
    # These payloads really end at EOF, without the Z/newline used below.
    # They are invalid UTF-8, but decode as complete cp1252 comment text.
    foreach {name hex expected} {
        eof_two   c2     "\u00c2"
        eof_three e282   "\u00e2\u201a"
        eof_four  f09f98 "\u00f0\u0178\u02dc"
    } {
        set expected [subst -nocommands -novariables $expected]
        add_case $name "-- A[binary format H* $hex]" "-- A$expected" 0 "A$expected" {} 1
    }
    add_case eof_after_entity "$body-- A[binary format H* e282]" \
        "$body-- A\u00e2\u201a" 1 "A\u00e2\u201a" Dut 3
    set text "-- caf\u00e9 \u20ac \u4e2d \ud83d\ude00\n$body"
    add_case utf8_text [encoding convertto utf-8 $text] $text 2 "caf\u00e9 \u20ac \u4e2d \ud83d\ude00"
    set literal "caf\u00e9 \u20ac \u4e2d"
    set text "${body}architecture rtl of Dut is\nbegin\nassert true report \"$literal\";\nend architecture rtl;"
    add_case utf8_literal [encoding convertto utf-8 $text] $text 1
    add_comment_case internal_bom 78efbbbf79 "x\ufeffy"

    # RFC 3629 boundaries: ASCII (including NUL), 2/3/4-byte sequences,
    # U+D7FF below the surrogate range, and the largest scalar U+10FFFF.
    foreach {name hex expected} {
        ascii          007f     "\u0000\u007f"
        two_min        c280     "\u0080"
        two_max        dfbf     "\u07ff"
        three_min      e0a080   "\u0800"
        below_surrogate ed9fbf  "\ud7ff"
        above_surrogate ee8080  "\ue000"
        three_max      efbfbf   "\uffff"
        four_min       f0908080 "\ud800\udc00"
        four_f1        f1808080 "\ud8c0\udc00"
        four_f3        f3bfbfbf "\udbbf\udfff"
        four_max       f48fbfbf "\udbff\udfff"
    } {
        add_comment_case $name $hex [subst -nocommands -novariables $expected]
    }

    # Invalid lead/continuation bytes, truncation, overlong encodings,
    # surrogate encodings, CESU-8, and values beyond U+10FFFF must all select
    # cp1252. A UTF-8 round trip alone would accept some of these in Tcl 8.6.
    foreach {name hex expected} {
        cp1252_text    e9208020937894 "\u00e9 \u20ac \u201cx\u201d"
        stray_cont     80           "\u20ac"
        short_two_with_suffix c2     "\u00c2"
        short_three_with_suffix e282 "\u00e2\u201a"
        short_four_with_suffix f09f98 "\u00f0\u0178\u02dc"
        bad_cont       e228a1       "\u00e2(\u00a1"
        bad_third      e28228       "\u00e2\u201a("
        bad_fourth     f0908028     "\u00f0\u0090\u20ac("
        overlong_nul   c080         "\u00c0\u20ac"
        overlong_two   c1bf         "\u00c1\u00bf"
        overlong_three e09fbf       "\u00e0\u0178\u00bf"
        surrogate      eda080       "\u00ed\u00a0\u20ac"
        cesu8          eda0bdedb880 "\u00ed\u00a0\u00bd\u00ed\u00b8\u20ac"
        overlong_four  f08fbfbf     "\u00f0\u008f\u00bf\u00bf"
        above_max      f4908080     "\u00f4\u0090\u20ac\u20ac"
        invalid_lead   f5808080     "\u00f5\u20ac\u20ac\u20ac"
        ff_lead        ff           "\u00ff"
        whole_file_fallback c3a92080 "\u00c3\u00a9 \u20ac"
    } {
        add_comment_case $name $hex [subst -nocommands -novariables $expected]
    }
    add_case bom_cp1252 "$bom-- [binary format H* 80]\n$body" "-- \u20ac\n$body" 2 "\u20ac"
    foreach {name newline} [list crlf "\r\n" cr "\r"] {
        set text "\n-- heading\n$body"
        set bytes "$bom[string map [list \n $newline] $text]"
        add_case $name $bytes $text 3 heading
    }

    foreach system_encoding {utf-8 cp1252} {
        with_system_encoding $system_encoding {
            foreach case $cases {
                lassign $case name path text line comment entities comment_line
                foreach lint {false true} {
                    set label "$system_encoding / $name / lint=$lint"
                    set ::lint_content "not called"
                    set rc [catch {
                        ::aurig::core::analyze::vhdlscan -in $path -lint $lint
                    } ast]
                    check_eq "$label parses" $rc 0
                    if {$rc} {puts "  $ast"; continue}
                    check_eq "$label entity" [::aurig::core::analyze::q_entity_names $ast] $entities
                    set entity [::aurig::core::analyze::q_entity $ast Dut]
                    set actual_line 0
                    set actual_comment ""
                    if {[dict exists $entity line]} {set actual_line [dict get $entity line]}
                    if {$comment_line eq ""} {set comment_line [expr {$line - 1}]}
                    if {[dict exists $ast comments line $comment_line comment]} {
                        set actual_comment [dict get $ast comments line $comment_line comment]
                    }
                    check_eq "$label line" $actual_line $line
                    check_eq "$label comment" $actual_comment $comment
                    if {$name eq "utf8_literal"} {
                        set arch [::aurig::core::analyze::q_arch_by_name $ast rtl]
                        set literal_kept 0
                        if {[dict exists $arch body_section]} {
                            set literal_kept [expr {[string first "\"$literal\"" [dict get $arch body_section]] >= 0}]
                        }
                        check_eq "$label literal" $literal_kept 1
                    }
                    if {$lint} {
                        # Observe the actual lint argument, before string trim:
                        # exactly one leading BOM removed, internal BOMs kept.
                        check_eq "$label lint input" $::lint_content $text
                    }
                }
            }
        }
        check_eq "$system_encoding restores encoding" [encoding system] $original_encoding
    }
    set rc [catch {with_system_encoding cp1252 {error "restoration probe"}} message]
    check_eq "error propagates" $rc 1
    check_eq "original error preserved" $message "restoration probe"
    check_eq "error restores encoding" [encoding system] $original_encoding
} finally {
    encoding system $original_encoding
    trace remove execution ::aurig::core::analyze::_validate_vhdl_lint_syntax enter capture_lint_content
    file delete -force -- $temp_dir
}
puts "\nEncoding regression: passed $passed, failed $failed"
exit [expr {$failed == 0 ? 0 : 1}]
