# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

namespace eval ::aurig::core::util {
    namespace export read_vhdl_source
}

namespace eval ::aurig::core::util::vhdl_source {
    variable block_size 65536
    variable offsets

    # RFC 3629 section 4. Apply the grammar to byte-valued characters and
    # exclude raw NUL from the ASCII run for the VHDL source interface.
    variable scalar [join {
        {[\xc2-\xdf][\x80-\xbf]}
        {\xe0[\xa0-\xbf][\x80-\xbf]}
        {[\xe1-\xec\xee-\xef][\x80-\xbf]{2}}
        {\xed[\x80-\x9f][\x80-\xbf]}
        {\xf0[\x90-\xbf][\x80-\xbf]{2}}
        {[\xf1-\xf3][\x80-\xbf]{3}}
        {\xf4[\x80-\x8f][\x80-\xbf]{2}}
    } |]
    variable prefix [format {\A[\x01-\x7f]*(?:(?:%s)[\x01-\x7f]*)*} $scalar]
    variable complete "${prefix}\\Z"
    unset scalar

    # Tcl 8.5's UTF-8 codec can decode surrogate code units but does not
    # decode standard four-byte sequences. Detect that codec behavior.
    variable native_supplementary [expr {
        [scan [encoding convertfrom utf-8 [binary format H* f09f9880]] %c] == 0x1f600
    }]
    # Tcl 8's bytearray string representation uses exactly one byte for
    # values 1..127, and two for NUL and high bytes. Tcl 9 lacks bytelength.
    variable has_byte_length [expr {[package vcompare [info tclversion] 9] < 0}]
}

proc ::aurig::core::util::read_vhdl_source {path} {
    # Tcl open treats a leading pipe as a pipeline. Treat it as a filename.
    set filename $path
    if {[string index $filename 0] eq "|"} {
        set filename [file join . $filename]
    }
    if {[catch {open $filename rb} channel options]} {
        return [vhdl_source::io_error $path OPEN $channel $options]
    }
    set read_code [catch {read $channel} bytes options]
    set close_code [catch {close $channel} close_message close_options]
    if {$read_code} {
        return [vhdl_source::io_error $path READ $bytes $options]
    }
    if {$close_code} {
        return [vhdl_source::io_error $path CLOSE $close_message $close_options]
    }

    # Keep the original bytearray intact, including the signature, for
    # offsets and conversion. Only inspect or convert bounded slices.
    set bom [expr {[string range $bytes 0 2] eq "\xef\xbb\xbf"}]
    set start [expr {$bom ? 3 : 0}]
    set invalid [vhdl_source::first_invalid $bytes $start]
    set codec utf-8
    if {$invalid >= 0} {
        binary scan $bytes @${invalid}c bad_byte
        if {$bad_byte == 0} {
            vhdl_source::nul_error $path $invalid
        }
        if {$bom} {
            return -code error -errorcode [list AURIG CORE SOURCE INVALID_UTF8 $invalid] \
                "Cannot decode VHDL source \"$path\": malformed UTF-8 at byte $invalid after the UTF-8 BOM; repair the sequence or resave as UTF-8"
        }
        set nul [vhdl_source::first_nul $bytes [expr {$invalid + 1}]]
        if {$nul >= 0} {
            vhdl_source::nul_error $path $nul
        }
        set codec cp1252
    }

    if {[catch {vhdl_source::decode $bytes $start $codec} text options]} {
        dict set options -errorcode [list AURIG CORE SOURCE DECODE [dict get $options -errorcode]]
        return -options $options "Cannot decode VHDL source \"$path\" as $codec: $text"
    }
    return [dict create text $text encoding $codec bom_removed $bom \
        fallback [expr {$codec eq "cp1252"}] invalid_utf8_offset $invalid]
}

proc ::aurig::core::util::vhdl_source::io_error {path stage message options} {
    dict set options -errorcode [list AURIG CORE SOURCE IO $stage [dict get $options -errorcode]]
    return -options $options "Cannot [string tolower $stage] VHDL source \"$path\": $message"
}

proc ::aurig::core::util::vhdl_source::nul_error {path offset} {
    return -code error -errorcode [list AURIG CORE SOURCE NUL $offset] \
        "Cannot decode VHDL source \"$path\": embedded NUL at byte $offset; remove the NUL or check the file's encoding"
}

# Return an exclusive end, extending the single nominal cut through up
# to three continuation bytes. A longer run necessarily contains an error.
proc ::aurig::core::util::vhdl_source::utf8_block_end {bytes start total} {
    variable block_size
    set end [expr {min($start + $block_size, $total)}]
    for {set extra 0} {$extra < 3 && $end < $total} {incr extra} {
        # 'c' reads a signed byte on Tcl 8.5 too. 0x80..0xBF is -128..-65.
        binary scan $bytes @${end}c byte
        if {$byte < -128 || $byte > -65} {
            break
        }
        incr end
    }
    return $end
}

# Return the original byte offset of the first malformed lead/stray tail
# or raw NUL. Byte-valued characters give a one-to-one index in each slice.
proc ::aurig::core::util::vhdl_source::first_invalid {bytes start} {
    variable has_byte_length
    variable complete
    variable prefix
    set total [string length $bytes]
    for {} {$start < $total} {set start $end} {
        set end [utf8_block_end $bytes $start $total]
        set block [string range $bytes $start [expr {$end - 1}]]
        if {$has_byte_length && [string bytelength $block] == $end - $start} {
            continue
        }
        if {![regexp -- $complete $block]} {
            regexp -indices -- $prefix $block match
            return [expr {$start + [lindex $match 1] + 1}]
        }
    }
    return -1
}

proc ::aurig::core::util::vhdl_source::first_nul {bytes start} {
    variable block_size
    set total [string length $bytes]
    for {} {$start < $total} {incr start $block_size} {
        set block [string range $bytes $start [expr {$start + $block_size - 1}]]
        set index [string first "\x00" $block]
        if {$index >= 0} {
            return [expr {$start + $index}]
        }
    }
    return -1
}

# An in-memory, read-only reflected channel over the retained bytearray.
# The generic Tcl channel handles incremental codec and EOL state.
proc ::aurig::core::util::vhdl_source::snapshot_channel {bytes start limit utf8 method channel args} {
    variable offsets
    switch -- $method {
        initialize {
            set offsets($channel) $start
            return {initialize finalize watch read}
        }
        finalize {unset offsets($channel)}
        watch {}
        read {
            set offset $offsets($channel)
            set end [expr {min($offset + [lindex $args 0], $limit)}]
            # Tcl 8.6 can misdecode a four-byte sequence at an input
            # buffer edge. Feed the codec only full validated scalars.
            while {$utf8 && $end > $offset && $end < $limit} {
                binary scan $bytes @${end}c byte
                if {$byte < -128 || $byte > -65} {
                    break
                }
                incr end -1
            }
            if {$end == $offset && $offset < $limit} {
                error "Snapshot channel buffer cannot hold the next UTF-8 scalar"
            }
            set offsets($channel) $end
            return [string range $bytes $offset [expr {$end - 1}]]
        }
    }
}

proc ::aurig::core::util::vhdl_source::decode {bytes start codec} {
    variable block_size
    variable native_supplementary
    if {$codec eq "utf-8" && !$native_supplementary} {
        return [decode_legacy_utf8 $bytes $start]
    }
    set channel [chan create read [list [namespace current]::snapshot_channel $bytes $start         [string length $bytes] [expr {$codec eq "utf-8"}]]]
    set read_code [catch {
        fconfigure $channel -encoding $codec -translation auto -eofchar {} -buffersize $block_size
        read $channel
    } text options]
    set close_code [catch {close $channel} message close_options]
    if {$read_code} {
        return -options $options $text
    }
    if {$close_code} {
        return -options $close_options $message
    }
    return $text
}

# On Tcl 8.5, decode BMP runs with the standard codec and construct a
# surrogate pair for each already-validated supplementary scalar. Keep
# both full scalars and CRLF together at the conversion cuts.
proc ::aurig::core::util::vhdl_source::decode_legacy_utf8 {bytes start} {
    set total [string length $bytes]
    set text {}
    for {} {$start < $total} {set start $end} {
        set end [utf8_block_end $bytes $start $total]
        if {$end < $total && [string range $bytes [expr {$end - 1}] $end] eq "\r\n"} {
            incr end
        }
        set raw [string range $bytes $start [expr {$end - 1}]]
        set decoded {}
        set from 0
        foreach match [regexp -all -inline -indices -- {[\xf0-\xf4][\x80-\xbf]{3}} $raw] {
            lassign $match first last
            append decoded [encoding convertfrom utf-8 [string range $raw $from [expr {$first - 1}]]]
            binary scan $raw @${first}cccc lead b c d
            set value [expr {(($lead & 7) << 18 | ($b & 63) << 12 | ($c & 63) << 6 | ($d & 63)) - 0x10000}]
            append decoded [format %c%c [expr {0xd800 + ($value >> 10)}] [expr {0xdc00 + ($value & 1023)}]]
            set from [expr {$last + 1}]
        }
        append decoded [encoding convertfrom utf-8 [string range $raw $from end]]
        append text [string map [list "\r\n" "\n" "\r" "\n"] $decoded]
    }
    return $text
}
