# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# -*- Tcl -*-
# ini_yaml.tcl — Convert between legacy HSL .ini and AURIG project.yaml
#
# Namespace:   ::aurig::core::util
# API:
#   ::aurig::core::util::ini2yaml  inIni  outYaml ?optionsDict?
#   ::aurig::core::util::yaml2ini  inYaml outIni
#
# Options (dict):
#   project_name            : string (defaults to top_level or filename stem)
#   require_exact_versions  : boolean (default 0)
#   debug_paths             : boolean (default 0)
#
# Design notes:
# - We now **preserve [libraries] verbatim** into YAML. The canonical AURIG key
#   is `external_libraries:` (preferred on read/emit); the legacy `libraries:`
#   name is still accepted and round-trips unchanged.
#   Your downstream parsers can decide what to ignore; the converter stays lossless.
# - We still *add* `file_sets` for convenience (based on non-ignore paths), but do not
#   remove or rewrite the library map.
#

namespace eval ::aurig::core::util { namespace export ini2yaml yaml2ini }

# ---- small dict helpers ------------------------------------------------------
proc ::aurig::core::util::dexists {D args}   { return [dict exists $D {*}$args] }
proc ::aurig::core::util::dget {D args}      { if {[dict exists $D {*}$args]} {return [dict get $D {*}$args]} ; return {} }
proc ::aurig::core::util::dgetdef {D def args} { if {[dict exists $D {*}$args]} {return [dict get $D {*}$args]} ; return $def }

# ---- misc helpers ------------------------------------------------------------
proc ::aurig::core::util::boolLike {s} {
    switch -- [string tolower [string trim $s]] {
        1 - true - yes - on  {return 1}
        0 - false - no - off {return 0}
        default {return -1}
    }
}
proc ::aurig::core::util::fileStem {p} {
    set b [file tail $p]; set d [string last "." $b]
    if {$d < 0} {return $b}; return [string range $b 0 $d-1]
}

# ---- INI parsing/writing -----------------------------------------------------
# `readIni` is the canonical INI parser. Semantics:
#   - section names are lowercased and trimmed;
#   - `#` line comments and blank lines are skipped;
#   - keys accept any non-`=` prefix (so dotted/hyphenated keys work);
#   - the first occurrence of a key under a section stores the raw value
#     as a scalar; subsequent occurrences accumulate into a proper Tcl
#     list. A small per-(section,key) tracking dict avoids the
#     historical pitfall where the second `lappend` on a scalar whose
#     value contains spaces (e.g. `C:/My Lib`) silently turned the
#     existing scalar into multiple list elements.
proc ::aurig::core::util::readIni {fname} {
    set f [open $fname r]; set txt [read $f]; close $f
    set current ""
    set out {}
    # `accumulated` is a 2-level nested dict: $section -> $key -> 1
    # whenever that (section, key) pair already holds a Tcl list and the
    # next duplicate must just `lappend` rather than promote a scalar.
    # Using a nested dict (rather than a flat "section/key" tag string)
    # is collision-safe even when section names or keys themselves
    # contain `/`. The per-section sub-dict is `dict unset` when a
    # section header is redeclared (rare but legal), so subsequent
    # duplicates in the redeclared section start with a clean slate.
    set accumulated [dict create]
    foreach line [split $txt "\n"] {
        set s [string trim $line]
        if {$s eq ""} continue
        if {[string index $s 0] eq "#"} continue
        if {[regexp {^\[(.+)\]$} $s -> sec]} {
            set current [string tolower [string trim $sec]]
            dict set out $current {}
            # Drop any accumulation markers carried over from a prior
            # declaration of this section, otherwise a stale
            # "already promoted" flag would suppress the necessary
            # scalar→list promotion the next time the same key is
            # written with two values.
            if {[dict exists $accumulated $current]} {
                dict unset accumulated $current
            }
            continue
        }
        if {$current ne "" && [regexp {^([^=]+?)\s*=\s*(.*)$} $s -> k v]} {
            set key [string trim $k]
            set val [string trim $v]

            if {[dict exists $out $current $key]} {
                set existing [dict get $out $current $key]
                if {![dict exists $accumulated $current $key]} {
                    # First duplicate: promote the existing scalar to a
                    # proper 1-element list before appending. Using
                    # `[list $existing]` guarantees the value survives
                    # subsequent `lappend`s even when it contains spaces
                    # or other Tcl-list-special characters.
                    set existing [list $existing]
                    dict set accumulated $current $key 1
                }
                lappend existing $val
                dict set out $current $key $existing
            } else {
                dict set out $current $key $val
            }
        }
    }
    return $out
}

# Legacy compatibility shim: `_ini2dict` used to be an independent INI
# parser in `util/common.tcl` with subtly different semantics
# (case-preserving section names, `\\`→`/` line-wide normalisation,
# auto-bracing of spaces-containing values, `\w+`-only key regex). No
# internal caller exercised those differences; the README's "Legacy
# Compatibility" section documents `ces::_ini2dict` as a namespace
# alias for callers that imported the old `ces::` API. The shim lives
# here (next to `readIni`) so a legacy script that sources only
# `util/common.tcl` does not get a dangling delegation when calling
# `_ini2dict`. The `allow_append` argument is accepted for backward
# compatibility but ignored: `readIni` always accumulates duplicate
# keys, which is what every internal caller already relied on.
proc ::aurig::core::util::_ini2dict {ini_file {allow_append 1}} {
    return [::aurig::core::util::readIni $ini_file]
}
namespace eval ::aurig::core::util { namespace export _ini2dict }

proc ::aurig::core::util::writeIni {fname inidict {header "# Created by Tcl"}} {
    set f [open $fname w]; fconfigure $f -translation lf
    puts $f $header
    puts $f "# This is a comment. Comments are lines starting with a # sign"
    foreach section [lsort [dict keys $inidict]] {
        puts $f "\t\[[string tolower $section]\]"
        set kv [dict get $inidict $section]
        foreach key [lsort [dict keys $kv]] {
            set value [dict get $kv $key]

            # Check if it's a proper TCL list with multiple elements
            # We need to be careful: a path with spaces looks like a list to TCL
            # So we check: is it a list AND does it have list structure (braces/multiple items)?
            set isList 0
            if {[catch {llength $value} len] == 0 && $len > 1} {
                # It might be a list, but verify it's not just a string with spaces
                # by checking if list operations preserve it
                if {[catch {lindex $value 0}] == 0} {
                    # Can index it - likely a real list
                    # Double-check: if we join and compare, does it change?
                    set rejoined [join $value " "]
                    if {$rejoined ne $value} {
                        set isList 1
                    }
                }
            }

            if {$isList} {
                # Value is a proper list - write each element on separate line
                foreach item $value {
                    puts $f "$key = $item"
                }
            } elseif {[string first ";" $value] >= 0} {
                # Single string with semicolons - split by semicolon
                set parts [split $value ";"]
                foreach part $parts {
                    set part [string trim $part]
                    if {$part ne ""} {
                        puts $f "$key = $part"
                    }
                }
            } else {
                # Single value (possibly with spaces) - write normally
                puts $f "$key = $value"
            }
        }
        puts $f ""
    }
    close $f
}

# ---- YAML emit (hand-rolled, dependency-free) --------------------------------
proc ::aurig::core::util::yamlQuote {s} {
    if {$s eq ""} {return "\"\""}
    if {[regexp {[:#\-\{\}\[\],&\*\?\|\<\>\=\!%\@`]|^\s|^(\-|\?)\s|: } $s]} {
        set qs [string map {\" \\\" \\ \\\\} $s]; return "\"$qs\""
    }
    if {[string is integer -strict $s] || [string is double -strict $s]} {return "\"$s\""}
    if {[::aurig::core::util::boolLike $s] != -1} {return "\"$s\""}
    return $s
}
proc ::aurig::core::util::yamlEmitKV {fd key value {indent 0}} {
    puts $fd "[string repeat {  } $indent]$key: $value"
}
proc ::aurig::core::util::yamlEmitMapStart {fd key {indent 0}} {
    puts $fd "[string repeat {  } $indent]$key:"
}
proc ::aurig::core::util::yamlEmitList {fd key listVals {indent 0}} {
    set pad [string repeat {  } $indent]
    puts $fd "$pad$key:"
    foreach v $listVals { puts $fd "$pad  - $v" }
}

# ---- YAML read: use tcllib::yaml if present; else minimal subset -------------
#
# readYamlMinimal: indentation-aware recursive YAML subset parser used when the
# tcllib `yaml` package is not available. Supports:
#   - nested mappings at arbitrary depth
#   - lists of scalars
#   - lists of mappings (multi-key list items, e.g. `- lib: work` followed by
#     sibling keys `src:` / `vhdl_std:` at the dash-aligned sub-indent)
#   - nested lists inside list items
#   - the "compact list" style where the `- ` sits at the same indent as the
#     parent key (common in hand-written manifests)
#   - quoted scalars (single or double quotes are stripped)
#   - inline `#` comments after a scalar value are stripped (LINT-PROJECT-DEBT-032);
#     YAML 1.1/1.2 require the `#` to be preceded by whitespace, and only unquoted
#     scalars are subject to inline-comment stripping (a `#` inside quotes is
#     preserved as a literal character). Full-line `#` comments are also skipped
#     during tokenisation in readYamlMinimal.
#
# Not supported (consumers either avoid them or rely on the real `yaml` package
# when richer features are needed): anchors/aliases, flow style, multi-line
# block scalars (`|`/`>`), tagged nodes, quoted keys with spaces.
proc ::aurig::core::util::_yaml_parse_scalar {raw} {
    set v [string trim $raw]
    # Quoted scalars: strip surrounding quotes, return content as-is.
    # YAML treats `#` inside quoted scalars as a literal character — no
    # comment stripping. The regex tolerates an optional trailing
    # whitespace + `#` comment AFTER the closing quote so a field like
    # `field: "value # preserved"   # trailing comment` parses to
    # `value # preserved` (the inner `#` is data, the trailing one is
    # stripped). LINT-PROJECT-DEBT-032 hardening — the simpler
    # `^"(.*)"$` form rejected the trailing-comment case and fell
    # through to the unquoted path which mangled the inner `#`.
    #
    # The trailing-comment subexpression is `\s+#.*` (NOT `\s*#.*`):
    # YAML requires `#` to be preceded by whitespace to count as a
    # comment delimiter, and the same rule applies AFTER a closing
    # quote. So `"value"#nocomment` does NOT match the quoted regex
    # (it falls through to the unquoted path, where the same `\s+#`
    # rule applies on `regsub`). Without the `\s+` requirement,
    # malformed inputs like `"x"#tail` would have been silently
    # accepted and stripped to `x` (Copilot PR #85 round-1 finding).
    if {[regexp {^"((?:[^"\\]|\\.)*)"(?:\s+#.*)?$} $v -> inner]} {
        return $inner
    }
    # YAML single-quoted scalars escape an embedded apostrophe by doubling
    # it (`'it''s'` → `it's`). The character class `(?:[^']|'')*` accepts
    # either non-quote chars OR a `''` pair; after stripping the outer
    # delimiters we collapse `''` back to `'` via `string map`. Without
    # this, `'it''s'` would not match the quoted regex and would fall
    # through to the unquoted path which returns the value with the outer
    # quotes still attached (Copilot PR #85 round-2 finding — pre-round-2
    # the single-quoted regex was `'([^']*)'` which rejected any embedded
    # apostrophe outright).
    if {[regexp {^'((?:[^']|'')*)'(?:\s+#.*)?$} $v -> inner]} {
        return [string map {'' '} $inner]
    }
    # Unquoted scalar: YAML reserves `#` as comment delimiter either at
    # the start of a value or preceded by whitespace (space or tab).
    # Strip from `^#` OR `\s+#` to end of value, then re-trim trailing
    # whitespace. `(?:^|\s+)#` covers both:
    #   - `key: # comment`       → scalar starts with `#` → empty value
    #   - `key: value # comment` → `\s+#` matches the inline-comment delim
    #   - `key: value#nocomment` → no whitespace before `#` → preserved
    # LINT-PROJECT-DEBT-032: surfaced by the 2026-05-25 Sentinel real-test
    # pass where a manifest field `project_root: ../..  # inline comment`
    # was read as the whole literal string (path + comment), producing an
    # opaque "Project root not found" error from a non-existent embedded-
    # comment directory. The bare-`#`-at-start form was caught by Copilot
    # PR #85 round-3 — without the `^|` branch a `key: # comment` line
    # parsed to the literal `# comment` value, contradicting the
    # "inline comments are stripped" promise.
    regsub {(?:^|\s+)#.*$} $v "" v
    return [string trim $v]
}

proc ::aurig::core::util::_yaml_parse_block {tokens_var idx_var indent} {
    upvar 1 $tokens_var tokens
    upvar 1 $idx_var idx

    if {$idx >= [llength $tokens]} { return {} }
    lassign [lindex $tokens $idx] tok_indent tok_content
    if {$tok_indent < $indent} { return {} }

    if {[string index $tok_content 0] eq "-"} {
        set list_indent $tok_indent
        set result [list]
        while {$idx < [llength $tokens]} {
            lassign [lindex $tokens $idx] cur_indent cur_content
            if {$cur_indent < $list_indent} { break }
            if {$cur_indent > $list_indent} { break }
            if {[string index $cur_content 0] ne "-"} { break }

            set rest [string trimleft [string range $cur_content 1 end]]
            incr idx

            if {$rest eq ""} {
                lappend result [::aurig::core::util::_yaml_parse_block tokens idx [expr {$list_indent + 1}]]
                continue
            }
            if {[regexp {^([A-Za-z0-9_-]+):(?:\s+(.*))?$} $rest -> key val]} {
                set item [dict create]
                set sub_indent [expr {$list_indent + 2}]
                if {$val ne ""} {
                    dict set item $key [::aurig::core::util::_yaml_parse_scalar $val]
                } elseif {$idx < [llength $tokens]} {
                    lassign [lindex $tokens $idx] nxt_indent nxt_content
                    if {$nxt_indent > $sub_indent || \
                        ($nxt_indent == $sub_indent && [string index $nxt_content 0] eq "-")} {
                        dict set item $key \
                            [::aurig::core::util::_yaml_parse_block tokens idx $nxt_indent]
                    } else {
                        dict set item $key ""
                    }
                } else {
                    dict set item $key ""
                }
                while {$idx < [llength $tokens]} {
                    lassign [lindex $tokens $idx] nxt_indent nxt_content
                    if {$nxt_indent != $sub_indent} { break }
                    if {[string index $nxt_content 0] eq "-"} { break }
                    if {![regexp {^([A-Za-z0-9_-]+):(?:\s+(.*))?$} $nxt_content -> nkey nval]} {
                        break
                    }
                    incr idx
                    if {$nval ne ""} {
                        dict set item $nkey [::aurig::core::util::_yaml_parse_scalar $nval]
                    } elseif {$idx < [llength $tokens]} {
                        lassign [lindex $tokens $idx] nxt2_indent nxt2_content
                        if {$nxt2_indent > $sub_indent || \
                            ($nxt2_indent == $sub_indent && [string index $nxt2_content 0] eq "-")} {
                            dict set item $nkey \
                                [::aurig::core::util::_yaml_parse_block tokens idx $nxt2_indent]
                        } else {
                            dict set item $nkey ""
                        }
                    } else {
                        dict set item $nkey ""
                    }
                }
                lappend result $item
            } else {
                lappend result [::aurig::core::util::_yaml_parse_scalar $rest]
            }
        }
        return $result
    }

    set map_indent $tok_indent
    set result [dict create]
    while {$idx < [llength $tokens]} {
        lassign [lindex $tokens $idx] cur_indent cur_content
        if {$cur_indent != $map_indent} { break }
        if {[string index $cur_content 0] eq "-"} { break }
        if {![regexp {^([A-Za-z0-9_-]+):(?:\s+(.*))?$} $cur_content -> key val]} {
            incr idx
            continue
        }
        incr idx
        if {$val ne ""} {
            dict set result $key [::aurig::core::util::_yaml_parse_scalar $val]
        } elseif {$idx < [llength $tokens]} {
            lassign [lindex $tokens $idx] nxt_indent nxt_content
            if {$nxt_indent > $map_indent} {
                dict set result $key [::aurig::core::util::_yaml_parse_block tokens idx $nxt_indent]
            } elseif {$nxt_indent == $map_indent && [string index $nxt_content 0] eq "-"} {
                dict set result $key [::aurig::core::util::_yaml_parse_block tokens idx $map_indent]
            } else {
                dict set result $key ""
            }
        } else {
            dict set result $key ""
        }
    }
    return $result
}

# Reject filenames that would cause Tcl `open` to spawn a subprocess
# (leading `|` is the pipeline-open syntax) and require a regular file.
# Call site validators (e.g. freeze::load_manifest) already enforce this
# for their public CLI inputs, but the YAML readers are reused by other
# tools and tests so we keep a defense-in-depth check here.
proc ::aurig::core::util::_yaml_validate_path {fname} {
    if {[string index $fname 0] eq "|"} {
        error "YAML path must not start with '|': $fname"
    }
    if {![file isfile $fname]} {
        error "YAML file not found or not a regular file: $fname"
    }
}

proc ::aurig::core::util::readYamlMinimal {fname} {
    ::aurig::core::util::_yaml_validate_path $fname
    set fh [open $fname r]
    set raw_lines [split [read $fh] "\n"]
    close $fh

    set tokens [list]
    foreach raw $raw_lines {
        set s [string trimright $raw]
        if {$s eq ""} { continue }
        if {[regexp {^\s*#} $s]} { continue }
        regexp {^( *)} $s -> ws
        set indent [string length $ws]
        set content [string range $s $indent end]
        lappend tokens [list $indent $content]
    }

    if {[llength $tokens] == 0} { return {} }
    set idx 0
    return [::aurig::core::util::_yaml_parse_block tokens idx 0]
}
# readYaml: tcllib `yaml` if present, else the readYamlMinimal lite parser.
#
# F2 BOUNDARY: this dual-mode helper is for SIMPLE / non-canonical YAML only.
# It MUST NOT be the entry point for canonical project manifests, because the
# lite fallback cannot parse the multi-key list items in file_sets/ip_cores and
# would silently mis-read them. EVERY project-mode entry that reads a manifest
# gates on tcllib FIRST (require_libs), so it fails loudly when `yaml` is absent
# rather than reaching the fallback below:
#   - ::aurig::core::schema::scan_project / load_manifest -> require_libs {yaml json}
#   - ::aurig::core::util::collect_project_files -format yaml (_collect_from_yaml)
#     -> ::aurig::core::schema::require_libs yaml
#   - ::aurig::core::util::yaml2ini (and its CLI wrapper) -> require_libs yaml
# When readYaml IS reached on any of those paths, tcllib `yaml` is already
# guaranteed present and the readYamlMinimal branch below is never taken there.
# (Round-1 note corrected: yaml2ini was previously OMITTED from this list and
# did silently reach the fallback on a manifest -- now gated; see FIX 2.)
proc ::aurig::core::util::readYaml {fname} {
    ::aurig::core::util::_yaml_validate_path $fname
    if {![catch {package require yaml}]} {
        set f [open $fname r]; set t [read $f]; close $f
        return [yaml::yaml2dict $t]
    }
    return [::aurig::core::util::readYamlMinimal $fname]
}

# ---- Mapping: INI -> YAML ----------------------------------------------------
proc ::aurig::core::util::mapIniToYaml {inidict opts} {
    set config    [::aurig::core::util::dget $inidict config]
    if {[dict exists $inidict external_libraries]} {
        set libraries [dict get $inidict external_libraries]
    } else {
        set libraries [::aurig::core::util::dget $inidict libraries]
    }
    set device    [::aurig::core::util::dget $inidict device]
    set generics  [::aurig::core::util::dget $inidict generics]

    set project_name  [::aurig::core::util::dgetdef $opts "" project_name]
    set require_exact [expr {[::aurig::core::util::dgetdef $opts 0 require_exact_versions]?1:0}]
    set debug_paths   [expr {[::aurig::core::util::dgetdef $opts 0 debug_paths]?1:0}]

    set workdir [::aurig::core::util::dgetdef $config "" workdir]
    set top     [::aurig::core::util::dgetdef $config "" top_level]
    if {$project_name eq ""} { set project_name [expr {$top ne "" ? $top : "fpga_project"}] }

    # tools
    set synth_kind [string tolower [::aurig::core::util::dgetdef $config "" synth_tool]]
    set synth_path [::aurig::core::util::dgetdef $config "" synth_path]
    set sim_kind   [string tolower [::aurig::core::util::dgetdef $config "" simulator]]
    set sim_path   [::aurig::core::util::dgetdef $config "" simulator_path]

    proc _splitExeBin {p} {
        if {$p eq ""} {return [list "" ""]}
        if {[file isdirectory $p]} {return [list "" $p]} else {return [list [file tail $p] [file dirname $p]]}
    }
    lassign [_splitExeBin $synth_path] synth_exe synth_bin
    lassign [_splitExeBin $sim_path]   sim_exe   sim_bin
    if {$synth_exe eq ""} {
        switch -- $synth_kind {
            vivado   {set synth_exe vivado}
            quartus  {set synth_exe quartus_sh}
            diamond  {set synth_exe diamond}
            ise      {set synth_exe ise}
            precision - synplify {set synth_exe $synth_kind}
            default {}
        }
    }

    # device
    set vendor [string tolower [::aurig::core::util::dgetdef $device [::aurig::core::util::dgetdef $device "" vendor] manufacturer]]
    set family [::aurig::core::util::dgetdef $device "" family]
    set part   [::aurig::core::util::dgetdef $device "" part]
    set speed  [::aurig::core::util::dgetdef $device "" speed]

    # Compose YAML
    set y {}
    dict set y project_name $project_name
    dict set y project_root $workdir
    dict set y top $top
    dict set y debug_paths [expr {$debug_paths ? true : false}]

    dict set y tool synth [dict create kind $synth_kind version "" exe $synth_exe env_script [dict create linux "" windows ""] bin_dir $synth_bin]
    if {$sim_kind ne "" || $sim_exe ne "" || $sim_bin ne ""} {
        dict set y tool sim [dict create kind $sim_kind version "" exe $sim_exe env_script [dict create linux "" windows ""] bin_dir $sim_bin]
    }
    dict set y require_exact_versions [expr {$require_exact ? true : false}]
    dict set y device vendor $vendor
    dict set y device family $family
    dict set y device part   $part
    if {$speed ne ""} { dict set y device speed $speed }

    # PRESERVE LIBRARIES VERBATIM
    if {$libraries ne "" && [dict size $libraries]} {
        dict set y libraries $libraries
    }

    # Also derive a helper file_sets (non-destructive)
    set file_sets {}
    set rtl_list {}
    if {$libraries ne ""} {
        foreach k [dict keys $libraries] {
            set v [dict get $libraries $k]
            if {[string tolower $v] eq "ignore"} continue
            set entry {}; dict set entry lib $k
            dict set entry src [list [file join $v "**" "*.vhd"] [file join $v "**" "*.vhdl"]]
            dict set entry include [list $v]
            dict set entry vhdl_std 2008
            lappend rtl_list $entry
        }
    }
    if {[llength $rtl_list]} { dict set file_sets rtl $rtl_list }
    if {[dict size $file_sets]} { dict set y file_sets $file_sets }

    # keep generics under env.generics (lossless, optional)
    if {$generics ne "" && [dict size $generics]} {
        dict set y env generics $generics
    }

    # NEW: board constraints from INI [board] section
    set board [::aurig::core::util::dget $inidict board]
    if {$board ne "" && [dict size $board]} {
        set xdc_files [::aurig::core::util::dget $board xdc_files]
        set sdc_files [::aurig::core::util::dget $board sdc_files]
        if {$xdc_files ne ""} {
            # Split comma-separated values if needed
            if {[string match "*,*" $xdc_files]} {
                set files {}
                foreach f [split $xdc_files ","] {
                    lappend files [string trim $f]
                }
                dict set y board xdc_files $files
            } elseif {[llength $xdc_files] == 1} {
                dict set y board xdc_files [list $xdc_files]
            } else {
                dict set y board xdc_files $xdc_files
            }
        }
        if {$sdc_files ne ""} {
            # Split comma-separated values if needed
            if {[string match "*,*" $sdc_files]} {
                set files {}
                foreach f [split $sdc_files ","] {
                    lappend files [string trim $f]
                }
                dict set y board sdc_files $files
            } elseif {[llength $sdc_files] == 1} {
                dict set y board sdc_files [list $sdc_files]
            } else {
                dict set y board sdc_files $sdc_files
            }
        }
    }

    # NEW: sim config from INI [sim] section
    set sim_section [::aurig::core::util::dget $inidict sim]
    if {$sim_section ne "" && [dict size $sim_section]} {
        set top_tb [::aurig::core::util::dget $sim_section top_tb]
        set tb_lib [::aurig::core::util::dget $sim_section tb_lib]
        set run_time [::aurig::core::util::dget $sim_section run_time]
        if {$top_tb ne ""} { dict set y sim top_tb $top_tb }
        if {$tb_lib ne ""} { dict set y sim tb_lib $tb_lib }
        if {$run_time ne ""} { dict set y sim run_time $run_time }
    }

    # NEW: global includes from INI [includes] section
    set includes [::aurig::core::util::dget $inidict includes]
    if {$includes ne "" && [dict size $includes]} {
        set global_inc [::aurig::core::util::dget $includes global]
        if {$global_inc ne ""} {
            # Split comma-separated values if needed
            if {[string match "*,*" $global_inc]} {
                set paths {}
                foreach p [split $global_inc ","] {
                    lappend paths [string trim $p]
                }
                dict set y include_dirs_global $paths
            } elseif {[llength $global_inc] == 1} {
                dict set y include_dirs_global [list $global_inc]
            } else {
                dict set y include_dirs_global $global_inc
            }
        }
    }

    return $y
}

# ---- Mapping: YAML -> INI ----------------------------------------------------
proc ::aurig::core::util::mapYamlToIni {ydict} {
    proc _g {D args} { if {[dict exists $D {*}$args]} {return [dict get $D {*}$args]} ; return "" }

    set inid {}

    # [config]
    set workdir   [_g $ydict project_root]
    set top       [_g $ydict top]
    set synth     [_g $ydict tool synth]
    set sim       [_g $ydict tool sim]
    set synth_kind [string tolower [_g $synth kind]]
    set synth_exe  [_g $synth exe]
    set synth_bin  [_g $synth bin_dir]
    if {$synth_bin eq "" && $synth_exe ne ""} {
        set synth_path $synth_exe
    } elseif {$synth_bin ne "" && $synth_exe ne ""} {
        set synth_path [file join $synth_bin $synth_exe]
    } else { set synth_path "" }

    set sim_kind [string tolower [_g $sim kind]]
    set sim_exe  [_g $sim exe]
    set sim_bin  [_g $sim bin_dir]
    if {$sim_bin eq "" && $sim_exe ne ""} {
        set sim_path $sim_exe
    } elseif {$sim_bin ne "" && $sim_exe ne ""} {
        set sim_path [file join $sim_bin $sim_exe]
    } else { set sim_path "" }

    dict set inid config workdir    $workdir
    dict set inid config top_level  $top
    dict set inid config synth_tool $synth_kind
    dict set inid config synth_path $synth_path
    if {$sim_kind ne ""} { dict set inid config simulator      $sim_kind }
    if {$sim_path ne ""} { dict set inid config simulator_path $sim_path }

    # [device]
    dict set inid device manufacturer [string tolower [_g $ydict device vendor]]
    dict set inid device family       [_g $ydict device family]
    dict set inid device part         [_g $ydict device part]
    if {[_g $ydict device speed] ne ""} { dict set inid device speed [_g $ydict device speed] }

    # [libraries] — if present in YAML, copy **verbatim**. Accept the canonical
    # AURIG name external_libraries (preferred) and the legacy libraries alias.
    # Presence, not non-emptiness, decides verbatim vs inference: an explicitly
    # present-but-empty map (e.g. external_libraries: {}) means "no libraries"
    # and must be preserved as such, never replaced by file_sets inference --
    # otherwise the lossless contract breaks and "no libraries" becomes
    # inexpressible.
    set libsPresent 1
    if {[dict exists $ydict external_libraries]} {
        set libsFromYaml [_g $ydict external_libraries]
    } elseif {[dict exists $ydict libraries]} {
        set libsFromYaml [_g $ydict libraries]
    } else {
        set libsPresent 0
        set libsFromYaml ""
    }
    if {$libsPresent} {
        dict set inid libraries $libsFromYaml
    } else {
        # otherwise best-effort infer from file_sets
        set libs {}
        set file_sets [_g $ydict file_sets]
        foreach fsName [dict keys $file_sets] {
            foreach entry [dict get $file_sets $fsName] {
                set lib  [_g $entry lib]
                set srcs [_g $entry src]
                set incs [_g $entry include]
                set base ""
                if {$incs ne "" && [llength $incs]} {
                    set base [lindex $incs 0]
                } elseif {$srcs ne "" && [llength $srcs]} {
                    set s0 [lindex $srcs 0]
                    set star [string first "**" $s0]
                    if {$star >= 0} {
                        set base [string trimright [string range $s0 0 [expr {$star-2}]] {/\\}]
                    } else {
                        set base [file dirname $s0]
                    }
                }
                if {$lib ne "" && $base ne ""} { dict set libs $lib $base }
            }
        }
        if {![dict size $libs]} {
            if {$workdir ne ""} { dict set libs work [file join $workdir src] } else { dict set libs work src }
        }
        dict set inid libraries $libs
    }

    # [generics] — from env.generics if present
    set gens [_g $ydict env generics]
    if {$gens ne "" && [dict size $gens]} { dict set inid generics $gens }

    # NEW: [board] — xdc/sdc files from YAML board section
    set board [_g $ydict board]
    if {$board ne ""} {
        set xdc_files [_g $board xdc_files]
        set sdc_files [_g $board sdc_files]
        if {$xdc_files ne ""} {
            if {[llength $xdc_files] == 1} {
                dict set inid board xdc_files [lindex $xdc_files 0]
            } else {
                dict set inid board xdc_files [join $xdc_files ", "]
            }
        }
        if {$sdc_files ne ""} {
            if {[llength $sdc_files] == 1} {
                dict set inid board sdc_files [lindex $sdc_files 0]
            } else {
                dict set inid board sdc_files [join $sdc_files ", "]
            }
        }
    }

    # NEW: [sim] — simulation config
    set sim_cfg [_g $ydict sim]
    if {$sim_cfg ne ""} {
        set top_tb [_g $sim_cfg top_tb]
        set tb_lib [_g $sim_cfg tb_lib]
        set run_time [_g $sim_cfg run_time]
        if {$top_tb ne ""} { dict set inid sim top_tb $top_tb }
        if {$tb_lib ne ""} { dict set inid sim tb_lib $tb_lib }
        if {$run_time ne ""} { dict set inid sim run_time $run_time }
    }

    # NEW: [includes] — global include directories
    set inc_global [_g $ydict include_dirs_global]
    if {$inc_global ne ""} {
        if {[llength $inc_global] == 1} {
            dict set inid includes global [lindex $inc_global 0]
        } else {
            dict set inid includes global [join $inc_global ", "]
        }
    }

    return $inid
}

# ---- YAML writer -------------------------------------------------------------
proc ::aurig::core::util::writeYaml {fname ydict} {
    set f [open $fname w]; fconfigure $f -translation lf
    proc _g {D args} { if {[dict exists $D {*}$args]} {return [dict get $D {*}$args]} ; return "" }

    foreach k {project_name project_root top} {
        set v [_g $ydict $k]; if {$v ne ""} { ::aurig::core::util::yamlEmitKV $f $k [::aurig::core::util::yamlQuote $v] }
    }
    if {[_g $ydict debug_paths] ne ""} {
        ::aurig::core::util::yamlEmitKV $f debug_paths [expr {[_g $ydict debug_paths] ? "true" : "false"}]
    }

    # tool
    set tool [_g $ydict tool]
    if {$tool ne ""} {
        ::aurig::core::util::yamlEmitMapStart $f tool
        foreach which {synth sim} {
            if {[_g $tool $which] eq ""} continue
            ::aurig::core::util::yamlEmitMapStart $f $which 1
            foreach k {kind version exe bin_dir} {
                set v [_g $tool $which $k]; if {$v ne ""} { ::aurig::core::util::yamlEmitKV $f $k [::aurig::core::util::yamlQuote $v] 2 }
            }
            if {[_g $tool $which env_script] ne ""} {
                ::aurig::core::util::yamlEmitMapStart $f env_script 2
                foreach os {linux windows} {
                    ::aurig::core::util::yamlEmitKV $f $os [::aurig::core::util::yamlQuote [_g $tool $which env_script $os]] 3
                }
            }
        }
    }

    if {[_g $ydict require_exact_versions] ne ""} {
        ::aurig::core::util::yamlEmitKV $f require_exact_versions [expr {[_g $ydict require_exact_versions] ? "true" : "false"}]
    }

    # device
    if {[_g $ydict device] ne ""} {
        ::aurig::core::util::yamlEmitMapStart $f device
        foreach k {vendor family part speed} {
            set v [_g $ydict device $k]; if {$v ne ""} { ::aurig::core::util::yamlEmitKV $f $k [::aurig::core::util::yamlQuote $v] 1 }
        }
    }

    # PRESERVE LIBRARIES VERBATIM (top-level map). Emit under whichever key the
    # dict carries -- the canonical AURIG external_libraries (preferred) or the
    # legacy libraries alias -- so a normalized manifest round-trips unchanged.
    set libsKey [expr {[dict exists $ydict external_libraries] ? "external_libraries" : "libraries"}]
    set libs [_g $ydict $libsKey]
    if {$libs ne "" && [dict size $libs]} {
        ::aurig::core::util::yamlEmitMapStart $f $libsKey
        foreach k [lsort [dict keys $libs]] {
            ::aurig::core::util::yamlEmitKV $f $k [::aurig::core::util::yamlQuote [dict get $libs $k]] 1
        }
    }

    # file_sets (optional helper)
    set file_sets [_g $ydict file_sets]
    if {$file_sets ne ""} {
        ::aurig::core::util::yamlEmitMapStart $f file_sets
        foreach fsName [lsort [dict keys $file_sets]] {
            ::aurig::core::util::yamlEmitKV $f $fsName "" 1
            foreach entry [dict get $file_sets $fsName] {
                puts $f "  - lib: [::aurig::core::util::yamlQuote [dict get $entry lib]]"
                set srcs [::aurig::core::util::dget $entry src]
                if {$srcs ne "" && [llength $srcs]} {
                    puts $f "    src:"; foreach s $srcs { puts $f "      - [::aurig::core::util::yamlQuote $s]" }
                }
                set incs [::aurig::core::util::dget $entry include]
                if {$incs ne "" && [llength $incs]} {
                    puts $f "    include:"; foreach inc $incs { puts $f "      - [::aurig::core::util::yamlQuote $inc]" }
                }
                if {[::aurig::core::util::dexists $entry vhdl_std]} {
                    puts $f "    vhdl_std: [::aurig::core::util::yamlQuote [dict get $entry vhdl_std]]"
                }
            }
        }
    }

    # NEW: board constraints
    set board [_g $ydict board]
    if {$board ne ""} {
        ::aurig::core::util::yamlEmitMapStart $f board
        set xdc [_g $board xdc_files]
        if {$xdc ne "" && [llength $xdc]} {
            ::aurig::core::util::yamlEmitList $f xdc_files $xdc 1
        }
        set sdc [_g $board sdc_files]
        if {$sdc ne "" && [llength $sdc]} {
            ::aurig::core::util::yamlEmitList $f sdc_files $sdc 1
        }
    }

    # NEW: global includes
    set inc_global [_g $ydict include_dirs_global]
    if {$inc_global ne "" && [llength $inc_global]} {
        ::aurig::core::util::yamlEmitList $f include_dirs_global $inc_global 0
    }

    # NEW: sim config
    set sim_cfg [_g $ydict sim]
    if {$sim_cfg ne ""} {
        ::aurig::core::util::yamlEmitMapStart $f sim
        foreach k {top_tb tb_lib run_time} {
            set v [_g $sim_cfg $k]
            if {$v ne ""} { ::aurig::core::util::yamlEmitKV $f $k [::aurig::core::util::yamlQuote $v] 1 }
        }
    }

    # env (optional: includes generics if any)
    if {[_g $ydict env] ne ""} {
        ::aurig::core::util::yamlEmitMapStart $f env
        if {[_g $ydict env generics] ne ""} {
            ::aurig::core::util::yamlEmitMapStart $f generics 1
            set gens [_g $ydict env generics]
            foreach gk [lsort [dict keys $gens]] {
                ::aurig::core::util::yamlEmitKV $f $gk [::aurig::core::util::yamlQuote [dict get $gens $gk]] 2
            }
        }
    }
    close $f
}

# ---- Public API --------------------------------------------------------------
proc ::aurig::core::util::ini2yaml {inIni outYaml args} {
    set opts [dict create]; if {[llength $args] > 0} { set opts [lindex $args 0] }
    set iniD [::aurig::core::util::readIni $inIni]
    set yD   [::aurig::core::util::mapIniToYaml $iniD $opts]
    ::aurig::core::util::writeYaml $outYaml $yD
}

proc ::aurig::core::util::yaml2ini {inYaml outIni} {
    # F2: yaml2ini reads a canonical project manifest (file_sets etc.), so it is
    # a project-mode YAML entry and MUST gate on tcllib `yaml` -- no silent
    # readYaml/readYamlMinimal fallback that would mis-parse multi-key list
    # items. When loaded as part of aurig::core we reuse the schema gate (the
    # canonical guidance); when this file is run STANDALONE via its CLI wrapper
    # (schema module not sourced) we degrade to a direct require with the same
    # loud-failure contract. Either way: no fallback to the lite parser.
    if {[llength [info commands ::aurig::core::schema::require_libs]]} {
        ::aurig::core::schema::require_libs yaml
    } elseif {[catch {package require yaml}]} {
        error "yaml2ini requires the tcllib 'yaml' package to parse a project\
 manifest; there is no safe lite-parser fallback for canonical YAML (multi-key\
 file_sets/ip_cores list items). Install tcllib (e.g. 'apt-get install tcllib')\
 and ensure it is on the Tcl auto_path."
    }
    set yD   [::aurig::core::util::readYaml $inYaml]
    set iniD [::aurig::core::util::mapYamlToIni $yD]
    set now [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    ::aurig::core::util::writeIni $outIni $iniD "# Created automatically by aurig::core::util on $now"
}

# ---- CLI wrapper -------------------------------------------------------------
if {[info exists argv0] && $argv0 eq [info script]} {
    if {[llength $argv] < 3} {
        puts stderr "Usage:"
        puts stderr "  tclsh [file tail $argv0] ini2yaml <input.ini>  <output.yaml> ?project_name=name? ?require_exact_versions=0? ?debug_paths=0?"
        puts stderr "  tclsh [file tail $argv0] yaml2ini <input.yaml> <output.ini>"
        exit 1
    }
    set cmd  [lindex $argv 0]
    set inF  [lindex $argv 1]
    set outF [lindex $argv 2]
    switch -- $cmd {
        ini2yaml {
            set opts {}; for {set i 3} {$i < [llength $argv]} {incr i} {
                if {[regexp {^([^=]+)=(.*)$} [lindex $argv $i] -> k v]} { dict set opts $k $v }
            }
            ::aurig::core::util::ini2yaml $inF $outF $opts
        }
        yaml2ini {
            ::aurig::core::util::yaml2ini $inF $outF
        }
        default { puts stderr "Unknown subcommand: $cmd"; exit 2 }
    }
}
