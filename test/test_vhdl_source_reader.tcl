# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

set test_dir [file dirname [file normalize [info script]]]
set core_root [file dirname $test_dir]
set auto_path [linsert $auto_path 0 $core_root]
package require aurig::core

namespace eval ::reader_test {
    variable checks 0
    variable reader ::aurig::core::util::read_vhdl_source
    variable dir [file join $::test_dir build "source_reader-[pid]-[clock clicks]"]
}

proc ::reader_test::equal {label actual expected} {
    variable checks
    if {$actual ne $expected} {
        error "$label: expected <$expected>, got <$actual>"
    }
    incr checks
}

proc ::reader_test::fixture {name bytes} {
    variable dir
    set path [file join $dir "$name.vhd"]
    set channel [open $path wb]
    puts -nonewline $channel $bytes
    close $channel
    return $path
}

proc ::reader_test::read_ok {path text {codec utf-8} {bom 0} {invalid -1}} {
    variable reader
    set channels [lsort [file channels]]
    set result [$reader $path]
    set label [file tail $path]
    equal "$label decoded text of [file size $path] input bytes matches" \
        [expr {[dict get $result text] eq $text}] 1
    equal "$label metadata" [list [dict get $result encoding] [dict get $result bom_removed] \
        [dict get $result fallback] [dict get $result invalid_utf8_offset]] \
        [list $codec $bom [expr {$codec eq "cp1252"}] $invalid]
    equal "$label channels after success" [lsort [file channels]] $channels
    return [dict get $result text]
}

proc ::reader_test::read_error {path reason offset} {
    variable reader
    set channels [lsort [file channels]]
    set code [catch {$reader $path} message options]
    equal "[file tail $path] raises" $code 1
    equal "[file tail $path] structured error" [dict get $options -errorcode] \
        [list AURIG CORE SOURCE $reason $offset]
    equal "[file tail $path] message includes path and byte offset" \
        [expr {[string first $path $message] >= 0 && [string first "byte $offset" $message] >= 0}] 1
    equal "[file tail $path] channels after error" [lsort [file channels]] $channels
}

proc ::reader_test::content_cases {} {
    set bom [binary format H* efbbbf]
    set empty [fixture empty {}]
    read_ok $empty {}
    read_ok [fixture plain "entity Dut is\r\n\t\r\nend;\r"] "entity Dut is\n\t\nend;\n"
    read_ok [fixture dos_eof "-- \x1a data\r\nentity Dut is\rend;"] "-- \x1a data\nentity Dut is\nend;"
    read_ok [fixture lf_only "a\n\nb\n"] "a\n\nb\n"
    read_ok [fixture consecutive_cr "a\r\r\nb\r\r"] "a\n\nb\n\n"
    read_ok [fixture bom_only $bom] {} utf-8 1
    read_ok [fixture signed "${bom}entity Dut is\nend;"] "entity Dut is\nend;" utf-8 1
    read_ok [fixture double_bom "$bom${bom}x$bom"] "\ufeffx\ufeff" utf-8 1
    read_ok [fixture internal_bom "x${bom}y"] "x\ufeffy"
    read_ok [fixture utf8 [binary format H* 636166c3a920e282ace4b8ad]] "caf\u00e9 \u20ac\u4e2d"
    read_ok [fixture cp1252 [binary format H* 636166e920809c]] "caf\u00e9 \u20ac\u0153" cp1252 0 3
    read_ok [fixture undefined [binary format H* 818d8f909d]] "\u0081\u008d\u008f\u0090\u009d" cp1252 0 0
    read_ok [fixture mixed [binary format H* c3a920800d0a78]] "\u00c3\u00a9 \u20ac\nx" cp1252 0 3
    read_ok [fixture structure "[binary format H* 80]entity Dut is\nend;"] "\u20acentity Dut is\nend;" cp1252 0 0
    read_error [fixture signed_malformed "$bom\xc3\xa9\r\nX\xe2\x82!"] INVALID_UTF8 8
    read_error [fixture nul "-- x\x00y\n"] NUL 4
    read_error [fixture signed_nul "${bom}a\r\n\x00"] NUL 6
    read_error [fixture nul_after_fallback "[binary format H* 80]abc\x00"] NUL 4
    read_error [fixture signed_bad_before_nul "$bom[binary format H* 80]abc\x00"] INVALID_UTF8 3

    # Supplementary scalars occupy two Tcl string indices on Tcl 8.x.
    set supplementary [fixture supplementary [binary format H* c3a920f09f98800958]]
    set text [read_ok $supplementary "\u00e9 \ud83d\ude00\tX"]
    equal "Tcl column after non-ASCII, supplementary scalar and a tab" [string first X $text] 5
    equal "Tcl length through that column" [string length $text] 6

    foreach {name hex value} {
        ascii_max 7f \u007f
        two_min c280 \u0080
        two_max dfbf \u07ff
        three_min e0a080 \u0800
        before_surrogates ed9fbf \ud7ff
        after_surrogates ee8080 \ue000
        three_max efbfbf \uffff
        four_min f0908080 \ud800\udc00
        four_max f48fbfbf \udbff\udfff
    } {
        set token [binary format H* $hex]
        read_ok [fixture $name $token] [subst -nocommands -novariables $value]
        for {set split 1} {$split < [string length $token]} {incr split} {
            # Exercise both a signed validation cut and a conversion cut.
            set pad [string repeat a [expr {65536 - $split}]]
            set expected "$pad[subst -nocommands -novariables $value]Z"
            read_ok [fixture "${name}_unsigned_$split" "$pad${token}Z"] $expected
            read_ok [fixture "${name}_signed_$split" "$bom$pad${token}Z"] $expected utf-8 1
        }
    }
    foreach {name hex decoded} {
        overlong_nul c080 \u00c0\u20ac
        overlong_two c1bf \u00c1\u00bf
        overlong_three e09fbf \u00e0\u0178\u00bf
        overlong_four f08fbfbf \u00f0\u008f\u00bf\u00bf
        high_surrogate eda080 \u00ed\u00a0\u20ac
        low_surrogate edb080 \u00ed\u00b0\u20ac
        cesu8 eda0bdedb880 \u00ed\u00a0\u00bd\u00ed\u00b8\u20ac
        out_of_range f4908080 \u00f4\u0090\u20ac\u20ac
        bad_lead f5808080 \u00f5\u20ac\u20ac\u20ac
        invalid_ff ff \u00ff
        wrong_tail e228a1 \u00e2(\u00a1
        truncated_two c2 \u00c2
        truncated_three e282 \u00e2\u201a
        truncated_four f09f98 \u00f0\u0178\u02dc
        stray_tail bf \u00bf
        extra_tail c2a280 \u00c2\u00a2\u20ac
    } {
        set token [binary format H* $hex]
        set invalid [expr {$name eq "extra_tail" ? 2 : 0}]
        read_ok [fixture $name "a$token"] "a[subst -nocommands -novariables $decoded]" cp1252 0 \
            [expr {1 + $invalid}]
        read_error [fixture "${name}_signed" "${bom}a$token"] INVALID_UTF8 [expr {4 + $invalid}]
    }
    foreach {label hex decoded offset} {
        lead_before_cut e28221 \u00e2\u201a! 65535
        too_many_tails f090808080 \u00f0\u0090\u20ac\u20ac\u20ac 65539
        missing_last f09080 \u00f0\u0090\u20ac 65535
        surrogate eda080 \u00ed\u00a0\u20ac 65535
    } {
        set pad [string repeat x 65535]
        set raw "$pad[binary format H* $hex]"
        read_ok [fixture "${label}_cut" $raw] "$pad[subst -nocommands -novariables $decoded]" \
            cp1252 0 $offset
        read_error [fixture "${label}_cut_signed" "$bom$raw"] INVALID_UTF8 [expr {$offset + 3}]
    }
    # Place CR as the final byte before the 64 KiB conversion cut.
    set pad [string repeat x 65535]
    read_ok [fixture crossing_crlf "$pad\r\ny"] "$pad\ny"
    read_ok [fixture crossing_legacy_crlf "\x80[string range $pad 1 end]\r\ny"] \
        "\u20ac[string range $pad 1 end]\ny" cp1252 0 0
    read_error [fixture late_nul "\x80$pad\x00"] NUL 65536

    set system_fixture [fixture system_encoding "$bom[binary format H* c3a920f09f98800d0a1a]"]
    set legacy_fixture [fixture system_legacy [binary format H* 61800d0a62]]
    set saved_encoding [encoding system]
    set code [catch {
        foreach codec {ascii cp1252 utf-8} {
            encoding system $codec
            read_ok $system_fixture "\u00e9 \ud83d\ude00\n\x1a" utf-8 1
            read_ok $legacy_fixture "a\u20ac\nb" cp1252 0 1
            equal "reader leaves the system codec $codec in place" [encoding system] $codec
        }
    } message options]
    encoding system $saved_encoding
    if {$code} {return -options $options $message}
}

proc ::reader_test::io_cases {} {
    variable dir
    variable reader
    set missing [file join $dir missing.vhd]
    set code [catch {$reader $missing} message options]
    equal "nonexistent input raises" $code 1
    equal "open failure category" [lrange [dict get $options -errorcode] 0 4] {AURIG CORE SOURCE IO OPEN}
    equal "open failure names path" [expr {[string first $missing $message] >= 0}] 1
    set existing [fixture io_input "x\r\n"]
    set legacy [fixture legacy_io [binary format H* 80]]
    if {$::tcl_platform(platform) ne "windows"} {
        set saved_dir [pwd]
        cd $dir
        set code [catch {
            fixture |source x
            read_ok |source.vhd x
        } message options]
        cd $saved_dir
        if {$code} {return -options $options $message}
    }
    set child [interp create]
    set code [catch {
        $child eval [list set auto_path $::auto_path]
        $child eval [list set path $existing]
        $child eval [list set reader $reader]
        $child eval [list set legacy $legacy]
        $child eval {
            package require aurig::core
            # The utility remains usable with the parser namespace absent.
            namespace delete ::aurig::core::analyze
        }
        equal "reader operates without the parser" [$child eval {dict get [$reader $path] text}] "x\n"
        $child eval {
            rename read original_read
            rename close original_close
            proc read {args} {
                if {$::fail_read} {
                    return -code error -errorcode {TEST READ} {injected read error}
                }
                return [uplevel 1 [list original_read {*}$args]]
            }
            proc close {channel} {
                original_close $channel
                if {$::fail_close} {
                    return -code error -errorcode {TEST CLOSE} {injected close error}
                }
            }
        }
        foreach {fail_read fail_close stage native} {
            1 0 READ READ
            1 1 READ READ
            0 1 CLOSE CLOSE
        } {
            $child eval [list set fail_read $fail_read]
            $child eval [list set fail_close $fail_close]
            lassign [$child eval {
                set before [lsort [file channels]]
                set rc [catch {$reader $path} message options]
                list $rc $message [dict get $options -errorcode] \
                    [expr {$before eq [lsort [file channels]]}]
            }] rc message error_code closed
            equal "$stage failure raises with flags $fail_read/$fail_close" $rc 1
            equal "$stage failure preserves native code" $error_code [list AURIG CORE SOURCE IO $stage [list TEST $native]]
            equal "$stage failure preserves native message" \
                [expr {[string first "injected [string tolower $native] error" $message] >= 0}] 1
            equal "$stage failure leaves no open channel" $closed 1
        }
        $child eval {
            proc read {channel} {
                if {[incr ::reads] == 2} {
                    return -code error -errorcode {TEST DECODE} {injected decode error}
                }
                return [original_read $channel]
            }
            set fail_close 0
            set reads 0
        }
        lassign [$child eval {
            set before [lsort [file channels]]
            set rc [catch {$reader $legacy} message options]
            list $rc [dict get $options -errorcode] \
                [expr {$before eq [lsort [file channels]]}] \
                [array size ::aurig::core::util::vhdl_source::offsets]
        }] rc error_code closed active
        equal "snapshot conversion failure raises" $rc 1
        equal "snapshot conversion failure preserves native code" $error_code {AURIG CORE SOURCE DECODE {TEST DECODE}}
        equal "snapshot conversion failure leaves no open channel" $closed 1
        equal "snapshot conversion failure clears channel state" $active 0

        # Replace the file once its byte snapshot has been read and closed.
        $child eval {
            proc close {channel} {
                original_close $channel
                if {!$::changed} {
                    set ::changed 1
                    set out [open $::path wb]
                    puts -nonewline $out "[binary format H* 80]different"
                    original_close $out
                }
            }
            rename read {}
            rename original_read read
            set changed 0
            set result [$reader $path]
        }
        equal "conversion uses the same snapshot after replacement" \
            [$child eval {list $changed [dict get $result text] [dict get $result encoding]}] \
            [list 1 "x\n" utf-8]
    } message options]
    interp delete $child
    if {$code} {return -options $options $message}
}

file mkdir $::reader_test::dir
set code [catch {
    ::reader_test::content_cases
    ::reader_test::io_cases
} message options]
file delete -force -- $::reader_test::dir
if {$code} {return -options $options $message}
puts "PASS: $::reader_test::checks assertions for the VHDL source reader on Tcl [info patchlevel]"
