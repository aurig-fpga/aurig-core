# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

set script_anchor [file dirname [file normalize [info script]]]
set core_root [file dirname $script_anchor]
lappend ::auto_path $core_root
package require aurig::core
::aurig::core::schema::require_libs yaml

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
    set fp [open $path w]
    fconfigure $fp -translation lf -encoding utf-8
    puts $fp $content
    close $fp
    return $path
}
proc expected_report {declared unmatched total present unexpanded} {
    dict create declared_patterns $declared unmatched_patterns $unmatched \
        total_files $total file_sets_present $present globs_unexpanded $unexpanded
}
proc exercise {name manifest expected args} {
    set plain [::aurig::core::util::collect_project_files -from $manifest {*}$args]
    set report stale
    set rc [catch {
        ::aurig::core::util::collect_project_files -from $manifest {*}$args -report report
    } reported options]
    check "$name: report call succeeds" {$rc == 0}
    if {$rc != 0} {
        puts "  $reported"
        return $plain
    }
    check "$name: returned inventory is byte-identical without -report" {$plain eq $reported}
    check "$name: report has exactly the five declared keys" {
        [lsort [dict keys $report]] eq [lsort [dict keys $expected]]
    }
    foreach key [dict keys $expected] {
        check "$name: $key" {[dict get $report $key] eq [dict get $expected $key]}
    }
    return $reported
}

set build_dir [file join $script_anchor build collect_project_files_report]
file mkdir [file join $build_dir src]
foreach name {a b c d e} {
    write_file [file join $build_dir src "$name.vhd"] "entity $name is end entity;"
}
write_file [file join $build_dir pins.xdc] {set_property PACKAGE_PIN A1 [get_ports clk]}
set all [write_file [file join $build_dir all.yaml] {project_root: .
file_sets:
  rtl:
    - lib: work
      src: [src/a.vhd, src/b.vhd, src/c.vhd]
  sim:
    - lib: tb
      src: [src/d.vhd, src/e.vhd]}]
exercise all_match $all [expected_report 5 {} 5 1 0] -format yaml
exercise auto_format $all [expected_report 5 {} 5 1 0]
exercise explicit_root $all [expected_report 5 {} 5 1 0] -root $core_root

set partial [write_file [file join $build_dir partial.yaml] {project_root: .
file_sets:
  rtl:
    - lib: work
      src: [src/a.vhd, src/b.vhd, src/c.vhd, src/d.vhd, 'missing\*.vhd']}]
exercise one_of_five_unmatched $partial [expected_report 5 [list {missing\*.vhd}] 4 1 0] -format yaml

set none [write_file [file join $build_dir none.yaml] {project_root: .
file_sets:
  rtl:
    - lib: work
      src: [missing/one.vhd, missing/two.vhd]
  sim:
    - lib: tb
      src: [missing/one.vhd]}]
exercise all_unmatched $none \
    [expected_report 3 [list missing/one.vhd missing/two.vhd missing/one.vhd] 0 1 0] -format yaml

set no_sets [file join $script_anchor fixtures project_files_report no_file_sets.yaml]
exercise no_file_sets $no_sets [expected_report 0 {} 0 0 0] -format yaml
set no_src [write_file [file join $build_dir no_src.yaml] {project_root: .
file_sets:
  rtl:
    - lib: work
  sim:
    - lib: tb}]
exercise groups_without_src $no_src [expected_report 0 {} 0 1 0] -format yaml

set board [write_file [file join $build_dir board.yaml] {project_root: .
board:
  xdc_files: [pins.xdc, missing-board.xdc]
  sdc_files: [missing-board.sdc]}]
exercise board_without_file_sets $board [expected_report 0 {} 1 0 0] -format yaml

# An inventory can be non-empty while zero sources are declared. A downstream
# gate must read declared_patterns rather than total_files.
set board_only [write_file [file join $build_dir board_only.yaml] {project_root: .
board:
  xdc_files: [pins.xdc]}]
exercise board_only_no_sources $board_only [expected_report 0 {} 1 0 0] -format yaml

set overlap [write_file [file join $build_dir overlap.yaml] {project_root: .
file_sets:
  rtl:
    - lib: first
      src: ['src/*.vhd']
  sim:
    - lib: second
      src: [src/a.vhd]
board:
  xdc_files: [pins.xdc, missing-board.xdc]}]
set files [exercise dedup_and_board $overlap [expected_report 2 {} 6 1 0] -format yaml]
set first_lib {}
dict for {key rec} $files {
    if {[dict get $rec name] eq "a.vhd"} {set first_lib [dict get $rec lib]}
}
check "dedup still retains the first library" {$first_lib eq "first"}

set files [exercise unexpanded_sources $partial [expected_report 5 {} 5 1 1] -format yaml -follow_globs 0]
set synthetic 0
dict for {key rec} $files {
    if {[dict exists $rec extra is_glob] && [dict get $rec extra is_glob]} {incr synthetic}
}
check "unexpanded source records retain is_glob" {$synthetic == 5}
exercise unexpanded_with_board $overlap [expected_report 2 {} 3 1 1] -format yaml -follow_globs 0
exercise unexpanded_no_file_sets $no_sets [expected_report 0 {} 0 0 1] -format yaml -follow_globs 0
exercise boolean_false $partial [expected_report 5 {} 5 1 1] -format yaml -follow_globs false
foreach zero {00 0.0 -0 0x0} {
    exercise "numeric_false_$zero" $partial [expected_report 5 {} 5 1 1] -format yaml -follow_globs $zero
}
exercise ignored_flag_without_sources $no_sets [expected_report 0 {} 0 0 {}] -format yaml -follow_globs invalid

set ini [write_file [file join $build_dir project.ini] [format {[config]
workdir = %s
[libraries]
work = src} $build_dir]]
exercise ini $ini [expected_report {} {} 5 0 0] -format ini
# The flag reports the requested option; INI keeps its existing expansion behavior.
exercise ini_follow_zero $ini [expected_report {} {} 5 0 1] -format ini -follow_globs 0
exercise ini_ignored_flag $ini [expected_report {} {} 5 0 {}] -format ini -follow_globs invalid
set ini_sets [write_file [file join $build_dir sections.ini] "[read [set fp [open $ini r]]]\n\[file_sets\]\nrtl = ignored"]
close $fp
exercise ini_top_level_section $ini_sets [expected_report {} {} 5 1 0] -format ini

set xpr [write_file [file join $build_dir project.xpr] {<Project>
<FileSet Name="sources_1"><File Path="src/a.vhd"><Attr Name="Library" Val="work"/></File></FileSet>
</Project>}]
exercise vivado $xpr [expected_report {} {} 1 0 0] -format vivado
set xise [write_file [file join $build_dir project.xise] {<project>
<file xil_pn:name="src/a.vhd" xil_pn:type="FILE_VHDL"></file>
</project>}]
exercise ise $xise [expected_report {} {} 1 0 0] -format ise
set qsf [write_file [file join $build_dir project.qsf] {set_global_assignment -name VHDL_FILE src/a.vhd
set_global_assignment -name VHDL_FILE missing.vhd}]
exercise quartus_records $qsf [expected_report {} {} 2 0 0] -format quartus
exercise quartus_missing_directory [file join $build_dir absent project.qpf] \
    [expected_report {} {} 0 0 0] -format quartus

set rc [catch {
    ::aurig::core::util::collect_project_files -from $all -report reports(files)
}]
check "report supports a caller array element" {$rc == 0 && [info exists reports(files)]}
namespace eval ::report_test {}
set rc [catch {
    ::aurig::core::util::collect_project_files -from $all -report ::report_test::files
}]
check "report supports a qualified caller variable" {$rc == 0 && [info exists ::report_test::files]}

puts "Passed: $passed"
puts "Failed: $failed"
exit [expr {$failed > 0}]
