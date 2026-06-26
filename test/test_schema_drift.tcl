#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.
#
# Drift / checksum guard for the vendored manifest-v1.json. Proves the guard
# (a) passes on the pinned byte-identical copy, (b) actually DETECTS a drifted
# copy (real tampered bytes, not a mock), and (c) the pinned SHA-256 constant
# matches an independent recomputation of the on-disk file.

set script_dir [file dirname [file normalize [info script]]]
set core_root  [file dirname $script_dir]
lappend ::auto_path $core_root
package require aurig::core

set ::pass 0
set ::fail 0
proc pass {name} { puts "  \[OK\]   $name"; incr ::pass }
proc fail {name msg} { puts "  \[XX\]   $name"; puts "         $msg"; incr ::fail }
proc check {name cond {detail ""}} {
    if {[uplevel 1 [list expr $cond]]} { pass $name } else { fail $name $detail }
}

puts "\n========== schema: vendored manifest drift guard =========="

if {[catch {package require sha256}]} {
    puts "FATAL: tcllib 'sha256' required for the drift guard test."
    exit 1
}

# (a) Pristine copy must pass.
if {[catch {::aurig::core::schema::verify_schema_checksum} e]} {
    fail "verify_schema_checksum passes on the pinned vendored copy" $e
} else {
    pass "verify_schema_checksum passes on the pinned vendored copy"
}

# (c) The pinned constant must equal an independent recomputation.
set real [::aurig::core::schema::schema_path]
set fh [open $real rb]; set bytes [read $fh]; close $fh
set recomputed [string tolower [::sha2::sha256 -hex $bytes]]
check "pinned schema_sha256 matches an independent recompute" \
    {$recomputed eq $::aurig::core::schema::schema_sha256} \
    "recomputed=$recomputed pinned=$::aurig::core::schema::schema_sha256"

# (b) A genuinely tampered copy must be DETECTED. Repoint the module's
# schema_file at a real, byte-modified temp file and assert the guard fires.
set tmp [file join $core_root test _tmp_drift_manifest.json]
set out [open $tmp wb]
puts -nonewline $out $bytes
puts -nonewline $out " "   ;# one extra byte -> different digest
close $out

set saved $::aurig::core::schema::schema_file
set ::aurig::core::schema::schema_file $tmp
set rc [catch {::aurig::core::schema::verify_schema_checksum} derr]
set ::aurig::core::schema::schema_file $saved
file delete -force $tmp

check "drift in the vendored copy is DETECTED" {$rc != 0} \
    "guard did not fire on a tampered file"
check "drift error is explicit about the checksum mismatch" \
    {[string match -nocase {*DRIFTED*} $derr]} "msg: $derr"

puts "\n========================================"
puts "  passed: $::pass    failed: $::fail"
puts "========================================"
exit [expr {$::fail == 0 ? 0 : 1}]
