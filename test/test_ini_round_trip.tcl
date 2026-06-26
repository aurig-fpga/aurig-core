# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Regression: INI parsing consolidation in `util/ini_yaml.tcl`.
#
# Pin three contracts so a future refactor cannot quietly diverge the two
# entry points or the read/write round-trip:
#   1. `::aurig::core::util::_ini2dict` (the legacy compatibility shim) MUST
#      delegate to `::aurig::core::util::readIni` and produce the same dict.
#   2. `readIni` semantics: section names are lowercased, duplicate keys
#      accumulate into a list, `#` comments and blank lines are skipped,
#      sections can repeat keys in any order.
#   3. `writeIni` → `readIni` round-trip preserves the semantically
#      relevant dict shape (modulo the writer's `lsort` of sections and
#      keys — values stay associated with their section/key).
#=============================================================================

set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_anchor]
lappend ::auto_path $aurig_core_root
package require aurig::core
set repo_root $aurig_core_root

set ::pass_count 0
set ::fail_count 0
set ::tmp_files {}

proc check {label cond} {
    if {[uplevel 1 [list expr $cond]]} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label"
        incr ::fail_count
    }
}

proc check_eq {label expected actual} {
    if {$expected eq $actual} {
        puts "PASS: $label"
        incr ::pass_count
    } else {
        puts "FAIL: $label"
        puts "  expected: <$expected>"
        puts "  actual:   <$actual>"
        incr ::fail_count
    }
}

proc tmp_ini {basename content} {
    set path [file join [file dirname [info script]] "_tmp_ini_${basename}.ini"]
    set fh [open $path w]
    fconfigure $fh -translation lf
    puts -nonewline $fh $content
    close $fh
    lappend ::tmp_files $path
    return $path
}

proc cleanup_tmp_files {} {
    foreach p $::tmp_files {
        catch {file delete -force $p}
    }
}

# ----------------------------------------------------------------------------
# Case 1: minimal INI — readIni parses sections, key=value pairs, comments,
# and skips blank lines.
# ----------------------------------------------------------------------------
set path [tmp_ini "minimal" {# This is a comment
[Config]
top_level = my_top
workdir = ./build

[Libraries]
work = src/rtl
ieee = ignore
}]

set d [::aurig::core::util::readIni $path]
check "minimal: dict has lowercased 'config' section" \
    {[dict exists $d config]}
check "minimal: dict has lowercased 'libraries' section" \
    {[dict exists $d libraries]}
check_eq "minimal: config.top_level" my_top [dict get $d config top_level]
check_eq "minimal: config.workdir" ./build [dict get $d config workdir]
check_eq "minimal: libraries.work" src/rtl [dict get $d libraries work]
check_eq "minimal: libraries.ieee" ignore [dict get $d libraries ieee]

# ----------------------------------------------------------------------------
# Case 2: duplicate keys accumulate into a list (the multi-path library
# pattern most consumers rely on).
# ----------------------------------------------------------------------------
set path [tmp_ini "duplicates" {[libraries]
work = src/rtl
work = src/components
work = ext/ip
}]

set d [::aurig::core::util::readIni $path]
set work [dict get $d libraries work]
check_eq "duplicates: three values accumulate into a list" 3 [llength $work]
check_eq "duplicates: first value preserved"  src/rtl       [lindex $work 0]
check_eq "duplicates: second value appended"  src/components [lindex $work 1]
check_eq "duplicates: third value appended"   ext/ip        [lindex $work 2]

# ----------------------------------------------------------------------------
# Case 2b: duplicate keys whose VALUES contain spaces (e.g. a Windows
# path like `C:/My Lib`). The naive `lappend $key $val` on an existing
# scalar would silently split the existing value into multiple list
# elements; the canonical reader now promotes the existing scalar to
# a proper 1-element list before appending. Pin both the count and
# the exact preserved elements.
# ----------------------------------------------------------------------------
set path [tmp_ini "duplicates_with_spaces" {[libraries]
work = C:/My Lib
work = ext/ip
work = third/value
}]

set d [::aurig::core::util::readIni $path]
set work [dict get $d libraries work]
check_eq "duplicates+spaces: three logical values preserved" \
    3 [llength $work]
check_eq "duplicates+spaces: first value with space preserved verbatim" \
    "C:/My Lib" [lindex $work 0]
check_eq "duplicates+spaces: second value preserved" \
    "ext/ip" [lindex $work 1]
check_eq "duplicates+spaces: third value preserved" \
    "third/value" [lindex $work 2]

# ----------------------------------------------------------------------------
# Case 2c (regression for the nested-dict accumulator change): the
# previous flat "section/key" tag string was vulnerable to two ways the
# "already promoted" flag could leak across boundaries it shouldn't:
#   (i)  a section name or key containing `/` produced colliding tags;
#   (ii) a section header that gets redeclared mid-file kept the stale
#        flag from its previous declaration, so the FIRST duplicate
#        after the redeclare would skip the scalar→list promotion and
#        re-introduce the space-splitting bug.
# Pin both scenarios.
# ----------------------------------------------------------------------------

# (i) Tag collision: section `[libs]` with key `multi/word`, AND a
# different section `[libs/multi]` with key `word`. The flat-tag form
# would write both into the same `libs/multi/word` slot.
set path [tmp_ini "tag_collision" {[libs]
multi/word = first value
multi/word = second

[libs/multi]
word = path with space
word = another
}]
set d [::aurig::core::util::readIni $path]
set v1 [dict get $d libs multi/word]
set v2 [dict get $d libs/multi word]
check_eq {tag collision: [libs] multi/word count} 2 [llength $v1]
check_eq {tag collision: [libs] first value preserved (with space)} \
    "first value" [lindex $v1 0]
check_eq {tag collision: [libs/multi] word count} 2 [llength $v2]
check_eq {tag collision: [libs/multi] first value preserved (with space)} \
    "path with space" [lindex $v2 0]

# (ii) Section redeclared mid-file. The first `work` write inside the
# second `[libraries]` block must be a scalar, and the second write
# inside that same block must still be promoted to a list (i.e. the
# accumulation marker from the first `[libraries]` block must have been
# cleared).
set path [tmp_ini "redeclared_section" {[libraries]
work = first/path
work = second/path

[libraries]
work = with space
work = no_space
}]
set d [::aurig::core::util::readIni $path]
set work [dict get $d libraries work]
check_eq "redeclared section: only the LAST declaration's values survive (count)" \
    2 [llength $work]
check_eq "redeclared section: first value of the redeclared block preserved verbatim" \
    "with space" [lindex $work 0]
check_eq "redeclared section: second value of the redeclared block preserved" \
    "no_space" [lindex $work 1]

# ----------------------------------------------------------------------------
# Case 3: `_ini2dict` is a thin shim — same input must produce the same dict.
# This is the consolidation contract; if a future refactor restores an
# independent parser, this assertion will fail.
# ----------------------------------------------------------------------------
set path [tmp_ini "shim_equiv" {# header
[CONFIG]
top_level = top
workdir = /abs/path
debug_paths = 1

[Libraries]
work = src
ieee = ignore
std  = ignore
work = build
}]

set via_canonical [::aurig::core::util::readIni $path]
set via_shim      [::aurig::core::util::_ini2dict $path]
check_eq "shim: _ini2dict returns exactly what readIni returns" \
    $via_canonical $via_shim

# The `allow_append` flag is accepted for backward compatibility but
# documented as ignored: explicit `0` must NOT change the result.
set via_shim_no_append [::aurig::core::util::_ini2dict $path 0]
check_eq "shim: allow_append=0 is ignored (compat shim, semantics fixed)" \
    $via_canonical $via_shim_no_append

# Regression: a legacy script that sources `util/common.tcl` directly
# (i.e. without going through init.tcl) must still get a usable
# `_ini2dict`. The shim in common.tcl is lazy: on first call it sources
# `ini_yaml.tcl` from the same directory and then delegates to
# `readIni`. The standalone-only scenario must work, and the also-source-
# ini_yaml-explicitly scenario must remain equivalent.
set common_path [file join $repo_root util common.tcl]
set ini_yaml_path [file join $repo_root util ini_yaml.tcl]

proc run_standalone_probe {sources path} {
    set runner [file join [file dirname [info script]] "_tmp_ini_standalone_runner.tcl"]
    lappend ::tmp_files $runner
    set lines [list]
    foreach src $sources {
        lappend lines "source [list $src]"
    }
    lappend lines "puts -nonewline \[::aurig::core::util::_ini2dict [list $path]\]"
    set fh [open $runner w]
    fconfigure $fh -translation lf
    puts $fh [join $lines "\n"]
    close $fh
    return [exec [info nameofexecutable] $runner 2>@1]
}

# Scenario A: only common.tcl is sourced. The lazy shim must auto-load
# ini_yaml.tcl on first _ini2dict call.
set probe_a [run_standalone_probe [list $common_path] $path]
check "standalone: _ini2dict callable after sourcing common.tcl ALONE (lazy load)" \
    {[string length $probe_a] > 0}
check "standalone: common.tcl-only result equals init.tcl-loaded result" \
    {$probe_a eq $via_canonical}

# Scenario B: both util files sourced explicitly (the "future-proof"
# pattern a legacy script may also use). Result must match.
set probe_b [run_standalone_probe [list $common_path $ini_yaml_path] $path]
check "standalone: common.tcl + ini_yaml.tcl together also work" \
    {$probe_b eq $via_canonical}

# Scenario C: common.tcl is sourced with a RELATIVE path, then the
# caller `cd`s away before the first `_ini2dict` call. The lazy load
# in common.tcl must still find `ini_yaml.tcl` because the sibling
# directory is captured absolutely at source time via
# `[file normalize [info script]]`. Drive this through a subprocess
# whose cwd starts at the util/ directory.
set rel_probe_runner [file join [file dirname [info script]] "_tmp_ini_relative_runner.tcl"]
lappend ::tmp_files $rel_probe_runner
set rel_lines [list \
    "set _start_dir \[pwd\]" \
    "source common.tcl" \
    "cd \[file dirname \$_start_dir\]" \
    "puts -nonewline \[::aurig::core::util::_ini2dict [list $path]\]"]
set fh [open $rel_probe_runner w]
fconfigure $fh -translation lf
puts $fh [join $rel_lines "\n"]
close $fh

# Subprocess cwd starts at $repo_root/util so `source common.tcl` is
# a relative-path source. The runner path is absolute so the cd
# doesn't make `exec` lose it. The runner itself uses an absolute
# fixture path (already baked into $path above).
set util_dir [file join $repo_root util]
set rel_probe_runner_abs [file normalize $rel_probe_runner]
set old_cwd [pwd]
cd $util_dir
set probe_c [exec [info nameofexecutable] $rel_probe_runner_abs 2>@1]
cd $old_cwd
check "standalone: relative source + later cd does not break lazy load" \
    {$probe_c eq $via_canonical}

# ----------------------------------------------------------------------------
# Case 4: writeIni → readIni round-trip. The writer is allowed to reorder
# sections / keys alphabetically (it explicitly `lsort`s them), so we
# compare the SHAPE of each section's key→value mapping rather than the
# raw dict equality.
# ----------------------------------------------------------------------------
set original [dict create \
    config [dict create top_level my_top workdir ./build debug_paths 1] \
    libraries [dict create work {src/rtl src/components} ieee ignore]]

set out_path [file join [file dirname [info script]] "_tmp_ini_rt.ini"]
lappend ::tmp_files $out_path
::aurig::core::util::writeIni $out_path $original "# Round-trip test"

set roundtrip [::aurig::core::util::readIni $out_path]

check "round-trip: config section survives" \
    {[dict exists $roundtrip config]}
check "round-trip: libraries section survives" \
    {[dict exists $roundtrip libraries]}
check_eq "round-trip: config.top_level preserved" \
    my_top [dict get $roundtrip config top_level]
check_eq "round-trip: config.workdir preserved" \
    ./build [dict get $roundtrip config workdir]
check_eq "round-trip: config.debug_paths preserved" \
    1 [dict get $roundtrip config debug_paths]
check_eq "round-trip: libraries.ieee preserved" \
    ignore [dict get $roundtrip libraries ieee]

set rt_work [dict get $roundtrip libraries work]
check_eq "round-trip: libraries.work multi-value count preserved" \
    2 [llength $rt_work]
check_eq {round-trip: libraries.work[0]} \
    src/rtl [lindex $rt_work 0]
check_eq {round-trip: libraries.work[1]} \
    src/components [lindex $rt_work 1]

# ----------------------------------------------------------------------------
# Case 5: keys with non-alphanumeric characters (dots, hyphens) — the
# canonical regex `^([^=]+?)\s*=\s*(.*)$` accepts any non-`=` key, so a
# manifest that uses dotted keys for tool versions or hyphenated lib
# names continues to parse.
# ----------------------------------------------------------------------------
set path [tmp_ini "non_alnum_keys" {[tool.synth]
vivado.version = 2024.1
vivado-path = C:/Xilinx/Vivado/2024.1
}]

set d [::aurig::core::util::readIni $path]
check_eq "non-alnum: section name lowercased verbatim" \
    {2024.1} [dict get $d tool.synth vivado.version]
check_eq "non-alnum: hyphenated key parses" \
    {C:/Xilinx/Vivado/2024.1} [dict get $d tool.synth vivado-path]

# ----------------------------------------------------------------------------
# Case 6: external_libraries is the canonical AURIG library-map key. The
# INI<->YAML converter must prefer it over the legacy libraries alias on both
# emit (writeYaml) and read-back (mapYamlToIni), while leaving a dict that
# only carries the legacy libraries key untouched (verbatim contract).
# ----------------------------------------------------------------------------
set out_yaml [file join [file dirname [info script]] "_tmp_extlib.yaml"]
lappend ::tmp_files $out_yaml
::aurig::core::util::writeYaml $out_yaml \
    [dict create project_name p top t \
        external_libraries [dict create acme /opt/acme ieee ignore]]
set yback [::aurig::core::util::readYaml $out_yaml]
check "extlib: writeYaml emits external_libraries key" \
    {[dict exists $yback external_libraries] && ![dict exists $yback libraries]}
check_eq "extlib: external_libraries.acme preserved" \
    /opt/acme [dict get $yback external_libraries acme]

set inid [::aurig::core::util::mapYamlToIni \
    [dict create project_name p top t \
        external_libraries [dict create acme /opt/acme]]]
check_eq {extlib: mapYamlToIni reads external_libraries into INI libraries} \
    /opt/acme [dict get $inid libraries acme]

# Present-but-empty external_libraries means "no libraries": it must be copied
# verbatim (an empty libraries map), NOT silently inferred from file_sets, or
# the lossless contract breaks and "no libraries" becomes inexpressible. The
# file_sets here would otherwise infer a non-empty libraries section.
set inid_empty [::aurig::core::util::mapYamlToIni \
    [dict create project_name p top t \
        external_libraries [dict create] \
        file_sets [dict create rtl [list [dict create lib work src [list rtl/a.vhd]]]]]]
check "extlib: present-but-empty external_libraries -> empty libraries (no inference)" \
    {[dict exists $inid_empty libraries] && [dict size [dict get $inid_empty libraries]] == 0}

# Legacy libraries-only dict still round-trips under libraries (verbatim).
set out_yaml2 [file join [file dirname [info script]] "_tmp_legacylib.yaml"]
lappend ::tmp_files $out_yaml2
::aurig::core::util::writeYaml $out_yaml2 \
    [dict create project_name p top t libraries [dict create work src/rtl]]
set yback2 [::aurig::core::util::readYaml $out_yaml2]
check "extlib: legacy libraries-only dict emits libraries key (verbatim)" \
    {[dict exists $yback2 libraries] && ![dict exists $yback2 external_libraries]}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
cleanup_tmp_files
puts ""
puts "============================================================"
puts "test_ini_round_trip.tcl"
puts "  passed: $::pass_count"
puts "  failed: $::fail_count"
puts "============================================================"
if {$::fail_count > 0} {
    exit 1
}
