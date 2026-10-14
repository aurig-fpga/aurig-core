# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# A manifest without project_root takes the schema default "." (the manifest
# dir), the same fallback scan_project applies. Every collection runs with the
# working directory OUTSIDE the manifest dir, so a cwd-relative resolution
# cannot pass by coincidence.

set script_anchor [file dirname [file normalize [info script]]]
set core_root [file dirname $script_anchor]
lappend ::auto_path $core_root
package require aurig::core
::aurig::core::schema::require_libs

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
proc write_file {path content} {
    file mkdir [file dirname $path]
    set fp [open $path w]
    fconfigure $fp -translation lf -encoding utf-8
    puts $fp $content
    close $fp
    return $path
}
# Lay out <dir>/<srcdir>/{a,b}.vhd and a manifest whose project_root line is
# `rootLine` ("" omits the key). Returns the manifest path.
proc make_case {dir rootLine {srcdir src}} {
    file delete -force $dir
    foreach name {a b} {
        write_file [file join $dir $srcdir $name.vhd] "entity $name is end entity;"
    }
    set body "schema_version: 1\nproject_name: demo\ntop: a\n"
    if {$rootLine ne ""} { append body "$rootLine\n" }
    append body "file_sets:\n  rtl:\n    - lib: work\n      src: \[src/a.vhd, src/b.vhd\]"
    return [write_file [file join $dir project.yaml] $body]
}
proc fullpaths {files} {
    set out {}
    dict for {k rec} $files { lappend out [file normalize [dict get $rec fullpath]] }
    return [lsort $out]
}
proc expected_paths {root} {
    return [lsort [list [file normalize [file join $root src a.vhd]] \
                        [file normalize [file join $root src b.vhd]]]]
}
# Collect, recording rc/message/errorcode in the caller's variables.
proc collect {manifest args} {
    upvar 1 rc rc res res opts opts
    set rc [catch {::aurig::core::util::collect_project_files -from $manifest {*}$args} res opts]
    if {$rc != 0} { puts "  rc=$rc: $res" }
}

# Resolved file_sets.rtl paths from the canonical pipeline (which merges the
# .local overlay), as {rc <code> paths <sorted list>}.
proc scan_rtl_paths {manifest} {
    if {[catch {::aurig::core::schema::scan_project $manifest} view]} {
        puts "  scan_project: $view"
        return [dict create rc 1 paths {}]
    }
    set paths {}
    foreach rec [dict get $view file_sets rtl] {
        lappend paths [file normalize [dict get $rec src]]
    }
    return [dict create rc 0 paths [lsort $paths]]
}

set build_dir [file join $script_anchor build collect_project_files_project_root]
file delete -force $build_dir
set elsewhere [file join $build_dir elsewhere]
file mkdir $elsewhere
set old_cwd [pwd]
cd $elsewhere

set absent_dir [file join $build_dir absent]
set absent [make_case $absent_dir ""]
set dot_dir [file join $build_dir dot]
set dot [make_case $dot_dir "project_root: ."]

# --- A: absent project_root, globs expanded -----------------------------------
collect $absent
check "A: absent project_root collects" {$rc == 0}
if {$rc == 0} {
    set a_paths [fullpaths $res]
    check "A: files resolve under the manifest dir" {$a_paths eq [expected_paths $absent_dir]}
}

# --- B: absent project_root, globs kept as patterns ---------------------------
collect $absent -follow_globs 0
check "B: absent project_root collects with -follow_globs 0" {$rc == 0}
if {$rc == 0} {
    check "B: patterns anchor at the manifest dir" {[fullpaths $res] eq [expected_paths $absent_dir]}
}

# --- C: absent project_root with -report --------------------------------------
set report stale
collect $absent -report ::report
check "C: absent project_root collects with -report" {$rc == 0}
if {$rc == 0} {
    check "C: report matches" {$report eq [dict create declared_patterns 2 \
        unmatched_patterns {} total_files 2 file_sets_present 1 globs_unexpanded 0]}
}

# --- D: parity with scan_project ----------------------------------------------
set scan [scan_rtl_paths $absent]
check "D: scan_project accepts the manifest" {[dict get $scan rc] == 0}
collect $absent
check "D: collector paths equal scan_project rtl paths" {
    $rc == 0 && [dict get $scan rc] == 0 && [fullpaths $res] eq [dict get $scan paths]
}

# --- Controls: explicit project_root forms ------------------------------------
collect $dot
check "control: project_root '.'" {$rc == 0 && [fullpaths $res] eq [expected_paths $dot_dir]}

set empty_dir [file join $build_dir empty]
set empty [make_case $empty_dir "project_root:"]
collect $empty
check "control: empty project_root" {$rc == 0 && [fullpaths $res] eq [expected_paths $empty_dir]}

set rel_dir [file join $build_dir relative]
set rel [make_case $rel_dir "project_root: sub" sub/src]
collect $rel
check "control: relative project_root" {
    $rc == 0 && [fullpaths $res] eq [expected_paths [file join $rel_dir sub]]
}

set abs_dir [file join $build_dir absolute]
set abs_root [file join $build_dir absolute_root]
set abs [make_case $abs_dir "project_root: '$abs_root'"]
foreach name {a b} {
    write_file [file join $abs_root src $name.vhd] "entity $name is end entity;"
}
collect $abs
check "control: absolute project_root" {$rc == 0 && [fullpaths $res] eq [expected_paths $abs_root]}

# --- Overlay: the collector does not merge project.local.yaml -----------------
set ovl_dir [file join $build_dir overlay_root]
set ovl [make_case $ovl_dir ""]
write_file [file join $ovl_dir project.local.yaml] "project_root: sub"
collect $ovl
check "overlay-only project_root fails" {$rc == 1}
check "overlay-only project_root raises a manifest error" {
    $rc == 1 && [dict get $opts -errorcode] eq {AURIG SCHEMA MANIFEST}
}
check "overlay-only project_root error names the overlay and scan_project" {
    $rc == 1 && [string match "*project.local.yaml*does not merge .local overlays*scan_project*" $res]
}

set ovl2_dir [file join $build_dir overlay_other]
set ovl2 [make_case $ovl2_dir ""]
write_file [file join $ovl2_dir project.local.yaml] "project_name: local"
collect $ovl2
check "overlay without project_root keeps the default" {
    $rc == 0 && [fullpaths $res] eq [expected_paths $ovl2_dir]
}

# The canonical merge skips empty overlay values (_is_empty), so an empty
# project_root in the overlay leaves the default in force for scan_project;
# the collector must agree rather than raise.
set ovl3_dir [file join $build_dir overlay_empty]
set ovl3 [make_case $ovl3_dir ""]
write_file [file join $ovl3_dir project.local.yaml] "project_root:"
collect $ovl3
check "overlay with empty project_root keeps the default" {
    $rc == 0 && [fullpaths $res] eq [expected_paths $ovl3_dir]
}
set scan [scan_rtl_paths $ovl3]
check "overlay with empty project_root: collector paths equal scan_project rtl paths" {
    $rc == 0 && [dict get $scan rc] == 0 && [fullpaths $res] eq [dict get $scan paths]
}

cd $old_cwd
puts "Passed: $passed"
puts "Failed: $failed"
exit [expr {$failed > 0}]
