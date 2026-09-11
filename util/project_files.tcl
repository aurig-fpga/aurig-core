# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# project_files.tcl
# Namespace : ::aurig::core::util
# Purpose   : Collect an inventory of design files from YAML, INI, Vivado .xpr,
#             or Quartus .qpf/.qsf. Returns a dict of file records.
#=============================================================================

namespace eval ::aurig::core::util {
    namespace export collect_project_files
}

# --- small helpers ------------------------------------------------------------

proc ::aurig::core::util::_norm {p} {
    if {$p eq ""} {return ""}
    return [string map {\\ /} $p]
}
proc ::aurig::core::util::_rel {full root} {
    if {$root eq ""} { return $full }

    # Normalize separators for comparison without depending on file normalize.
    set fullN [string map {\\ /} $full]
    set rootN [string map {\\ /} $root]

    # Try tcllib fileutil::relative if available
    if {![catch {package require fileutil}]} {
        if {![catch {fileutil::relative $rootN $fullN} rel]} {
            return [file join {*}[file split $rel]]
        }
    }

    # Fallback: manual relative path calculation
    # Convert to lowercase for case-insensitive comparison on Windows
    set fullL [string tolower $fullN]
    set rootL [string tolower $rootN]

    # Check if full path starts with root
    if {[string match "${rootL}*" $fullL]} {
        set cut [string length $rootN]
        set rel [string range $fullN $cut end]
        # Clean up leading slashes
        set rel [string trimleft $rel {/\\}]
        return $rel
    }

    # If not under root, return just the filename
    return [file tail $fullN]
}
proc ::aurig::core::util::_ext {p} {
    set e [string tolower [file extension $p]]
    if {$e eq ""} {return ""}
    return [string range $e 1 end]
}
proc ::aurig::core::util::_detect_type {ext} {
    # Be conservative: avoid "switch a - b { ... }" chaining (causes errors on some builds)
    set e [string tolower $ext]
    if {[lsearch -exact {vhd vhdl} $e] >= 0}         {return "vhdl"}
    if {[lsearch -exact {v verilog} $e] >= 0}        {return "verilog"}
    if {[lsearch -exact {sv svh systemverilog} $e] >= 0} {return "systemverilog"}
    if {$e eq "xdc"} {return "xdc"}
    if {$e eq "ucf"} {return "ucf"}
    if {$e eq "sdc"} {return "sdc"}
    if {$e eq "qip"} {return "qip"}
    if {$e eq "xco"} {return "xco"}
    if {$e eq "ngc"} {return "ngc"}
    if {$e eq "tcl"} {return "tcl"}
    return "other"
}

# Expand glob patterns used by project YAML/INI file inventories.
#
# Tcl's native glob does not implement recursive globstar. aurig supports
# `**` only as a complete path component, where it matches zero or more
# directories. Examples:
#   **/*.vhd          matches files in the base directory and below
#   src/**/*.vhd      matches src/top.vhd and src/sub/deep/foo.vhd
#   src/**/test/*.vhd matches any test directory under src, including src/test
#
# Patterns where `**` appears inside a component, such as `s**/*.vhd` or
# `**foo/*.vhd`, fail explicitly because their semantics are not supported.
proc ::aurig::core::util::_validate_globstar_components {pattern} {
    foreach part [file split [string map {\\ /} $pattern]] {
        if {[string match {*\*\**} $part] && $part ne "**"} {
            error "** must be a complete path component in glob pattern: $pattern"
        }
    }
}

proc ::aurig::core::util::_manual_find_dirs {base {depth 0} {max_depth 32}} {
    if {$depth > $max_depth} {
        error "Recursive glob exceeded maximum depth $max_depth at: $base"
    }

    set base [string map {\\ /} $base]
    set results [list $base]
    foreach child [glob -nocomplain -types d -- [file join $base *]] {
        lappend results {*}[::aurig::core::util::_manual_find_dirs $child [expr {$depth + 1}] $max_depth]
    }
    return $results
}

proc ::aurig::core::util::_find_dirs_for_globstar {base} {
    set base [string map {\\ /} $base]

    if {![catch {package require fileutil}] && [llength [info commands ::fileutil::find]]} {
        if {![catch {
            set dirs [list $base]
            foreach item [::fileutil::find $base] {
                if {[file isdirectory $item]} {
                    lappend dirs [string map {\\ /} $item]
                }
            }
            set dirs
        } found]} {
            return $found
        }
    }

    return [::aurig::core::util::_manual_find_dirs $base]
}

proc ::aurig::core::util::_expand_glob_pattern {pattern} {
    set pattern [string map {\\ /} $pattern]
    ::aurig::core::util::_validate_globstar_components $pattern

    set parts [file split $pattern]
    set star_index [lsearch -exact $parts "**"]
    if {$star_index < 0} {
        return [glob -nocomplain $pattern]
    }

    set prefix_parts [lrange $parts 0 [expr {$star_index - 1}]]
    set suffix_parts [lrange $parts [expr {$star_index + 1}] end]
    set prefix [file join {*}$prefix_parts]
    if {$prefix eq ""} {
        set prefix "."
    }

    set matches [list]
    foreach base [glob -nocomplain -types d $prefix] {
        foreach dir [::aurig::core::util::_find_dirs_for_globstar $base] {
            if {[llength $suffix_parts] == 0} {
                lappend matches $dir
            } else {
                set suffix [file join {*}$suffix_parts]
                lappend matches {*}[::aurig::core::util::_expand_glob_pattern [file join $dir $suffix]]
            }
        }
    }

    return [lsort -unique $matches]
}

# --- YAML / INI readers (reuse your earlier utilities if sourced) -------------
# Expect these to exist if you included the previous file; else provide fallbacks.

if {![llength [info procs ::aurig::core::util::readYaml]]} {
    proc ::aurig::core::util::readYaml {fname} {
        if {![catch {package require yaml}]} {
            set f [open $fname r]; set txt [read $f]; close $f
            return [yaml::yaml2dict $txt]
        } else {
            error "readYaml requires tcllib yaml or include previous util file"
        }
    }
}
# --- YAML source --------------------------------------------------------------

proc ::aurig::core::util::_collect_from_yaml {yamlPath root follow {reportVar ""}} {
    # F2: project-mode YAML loading MUST NOT silently fall back to
    # readYamlMinimal. This collector reads canonical-manifest-shaped YAML
    # (file_sets with multi-key list items that readYamlMinimal cannot parse),
    # so it requires tcllib `yaml` and fails LOUDLY with the same guidance as
    # the schema pipeline when it is absent -- closing the silent-bypass that
    # `readYaml`'s lite fallback would otherwise open here. NOTE: this collector
    # remains a file-INVENTORY tool and intentionally does NOT run schema
    # normalize/validate (it also accepts looser project YAML lacking the
    # canonical required keys); canonical-manifest consumers that need
    # normalize+validate use ::aurig::core::schema::scan_project. Decision recorded
    # in the PR description and doc/developer/status.md.
    ::aurig::core::schema::require_libs yaml
    set y [::aurig::core::util::readYaml $yamlPath]
    if {$reportVar ne ""} {
        upvar 1 $reportVar report
        set report [dict create declared_patterns 0 unmatched_patterns {} \
            file_sets_present [dict exists $y file_sets]]
    }
    # project_root might be relative to YAML
    set yamlDir [file dirname $yamlPath]
    set projRoot [dict get $y project_root]
    set projRoot [string map {\\ /} $projRoot]
    if {$projRoot eq ""} {
        set projRoot $yamlDir
    } elseif {$projRoot eq "."} {
        set projRoot $yamlDir
    } elseif {![string equal [file pathtype $projRoot] "absolute"]} {
        set projRoot [file join $yamlDir $projRoot]
    }
    if {$root eq ""} { set root $projRoot }

    set out {}
    set idx 0
    # File sets are a list of entries containing lib/src/include/vhdl_std
    if {[dict exists $y file_sets]} {
        dict for {fsName entries} [dict get $y file_sets] {
            foreach entry $entries {
                set lib       [dict get $entry lib]
                set vhdl_std  [expr {[dict exists $entry vhdl_std] ? [dict get $entry vhdl_std] : ""}]
                set srcGlobs  [expr {[dict exists $entry src] ? [dict get $entry src] : {}}]
                if {$reportVar ne ""} { dict incr report declared_patterns [llength $srcGlobs] }

                if {$follow} {
                    # Expand globs relative to projRoot
                    foreach g $srcGlobs {
                        set gabs $g
                        set gabs [string map {\\ /} $gabs]
                        if {![string equal [file pathtype $gabs] "absolute"]} {
                            set gabs [file join $projRoot $gabs]
                        }
                        set matches [::aurig::core::util::_expand_glob_pattern $gabs]
                        if {$reportVar ne "" && [llength $matches] == 0} {
                            dict lappend report unmatched_patterns $g
                        }
                        foreach f $matches {
                            set full [string map {\\ /} $f]
                            set rel  [::aurig::core::util::_rel $full $root]
                            set ext  [::aurig::core::util::_ext $full]
                            set rec [dict create \
                                name [file tail $full] \
                                ext  $ext \
                                type [::aurig::core::util::_detect_type $ext] \
                                lib  [expr {$lib eq "" ? "work" : $lib}] \
                                fullpath $full \
                                relpath  $rel \
                                vhdl_std $vhdl_std \
                                srcset   $fsName \
                                origin   yaml \
                                extra {}]
                            dict set out f$idx $rec
                            incr idx
                        }
                    }
                } else {
                    # Keep as patterns (one synthetic record per pattern)
                    foreach g $srcGlobs {
                        set full $g
                        set full [string map {\\ /} $full]
                        if {![string equal [file pathtype $full] "absolute"]} {
                            set full [file join $projRoot $full]
                        }
                        set rel  [::aurig::core::util::_rel $full $root]
                        set ext  [::aurig::core::util::_ext $full]
                        set rec [dict create \
                            name [file tail $full] \
                            ext  $ext \
                            type [::aurig::core::util::_detect_type $ext] \
                            lib  [expr {$lib eq "" ? "work" : $lib}] \
                            fullpath $full \
                            relpath  $rel \
                            vhdl_std $vhdl_std \
                            srcset   $fsName \
                            origin   yaml \
                            extra [dict create is_glob 1]]
                        dict set out f$idx $rec
                        incr idx
                    }
                }
            }
        }
    }

    # Optional: constraints from board.{xdc_files,sdc_files}
    foreach key {xdc_files sdc_files} {
        if {[dict exists $y board $key]} {
            foreach g [dict get $y board $key] {
                set full $g
                set full [string map {\\ /} $full]
                if {![string equal [file pathtype $full] "absolute"]} {
                    set full [file join $projRoot $full]
                }
                foreach f [::aurig::core::util::_expand_glob_pattern $full] {
                    set fullN [string map {\\ /} $f]
                    set rel  [::aurig::core::util::_rel $fullN $root]
                    set ext  [::aurig::core::util::_ext $fullN]
                    set rec [dict create \
                        name [file tail $fullN] \
                        ext  $ext \
                        type [::aurig::core::util::_detect_type $ext] \
                        lib  work \
                        fullpath $fullN \
                        relpath  $rel \
                        vhdl_std "" \
                        srcset   board \
                        origin   yaml \
                        extra {}]
                    dict set out f$idx $rec
                    incr idx
                }
            }
        }
    }

    return $out
}

# --- INI source ---------------------------------------------------------------

proc ::aurig::core::util::_collect_from_ini {iniPath root {reportVar ""}} {
    set ini [::aurig::core::util::readIni $iniPath]
    if {$reportVar ne ""} {
        upvar 1 $reportVar report
        # INI sections are top-level keys; XML/Quartus have no file_sets key.
        dict set report file_sets_present [dict exists $ini file_sets]
    }
    set workdir [expr {[dict exists $ini config workdir] ? [dict get $ini config workdir] : [file dirname $iniPath]}]
    if {$root eq ""} { set root $workdir }

    set libs  [expr {[dict exists $ini external_libraries] ? [dict get $ini external_libraries] \
                  : ([dict exists $ini libraries] ? [dict get $ini libraries] : {})}]
    set out {}; set idx 0

    # For each lib path (except ignore) glob typical sources
    dict for {lib p} $libs {
        if {[string tolower $p] eq "ignore"} continue
        set base $p
        if {![string equal [file pathtype $base] "absolute"]} {
            set base [::aurig::core::util::resolve_path $base $workdir]
        }
        foreach g {**/*.vhd **/*.vhdl **/*.v **/*.sv **/*.svh} {
            foreach f [::aurig::core::util::_expand_glob_pattern [file join $base $g]] {
                set full $f
                set rel  [::aurig::core::util::_rel $full $root]
                set ext  [::aurig::core::util::_ext $full]
                set rec [dict create \
                    name [file tail $full] \
                    ext  $ext \
                    type [::aurig::core::util::_detect_type $ext] \
                    lib  $lib \
                    fullpath $full \
                    relpath  $rel \
                    vhdl_std "" \
                    srcset   rtl \
                    origin   ini \
                    extra {}]
                dict set out f$idx $rec
                incr idx
            }
        }
    }
    return $out
}

# --- Vivado .xpr (XML) -------------------------------------------------------
# We avoid a full XML parser; regex is enough for typical XPRs.
# We look for:
#   <File Path="path/to/file.vhd"> ... <Attr Name="Library" Val="mylib"/>
#   and fileset names like: <FileSet Name="sources_1" Type="DesignSrcs">
proc ::aurig::core::util::_collect_from_vivado_xpr {xprPath root} {
    # Backward compatibility: a relative -from path still resolves through
    # file normalize. Manifest-internal entries below use explicit project
    # directory anchoring via resolve_path.
    set projDir [file dirname [file normalize $xprPath]]
    if {$root eq ""} { set root $projDir }
    set f [open $xprPath r]; set xml [read $f]; close $f

    set out {}; set idx 0

    # capture fileset blocks
    set filesetRE {<FileSet[^>]*Name="([^"]+)"[^>]*>(.*?)</FileSet>}
    set fileRE    {<File\s+Path="([^"]+)"[^>]*>(.*?)</File>}
    set libRE     {<Attr\s+Name="Library"\s+Val="([^"]+)"\s*/>}

    set start 0
    while {[regexp -indices -start $start -nocase $filesetRE $xml m fsName fsBlock]} {
        set start [lindex $m 1]
        set fsNameVal [string range $xml [lindex $fsName 0] [lindex $fsName 1]]
        set block     [string range $xml [lindex $fsBlock 0] [lindex $fsBlock 1]]

        set pos 0
        while {[regexp -indices -start $pos -nocase $fileRE $block m fPath fInner]} {
            set pos [lindex $m 1]
            set relPath [string range $block [lindex $fPath 0] [lindex $fPath 1]]
            # Most paths are relative to project dir
            set full [::aurig::core::util::resolve_path $relPath $projDir]
            set inner [string range $block [lindex $fInner 0] [lindex $fInner 1]]
            set lib "work"
            if {[regexp -nocase $libRE $inner -> L]} { set lib $L }
            set ext [::aurig::core::util::_ext $full]
            set rec [dict create \
                name [file tail $full] \
                ext  $ext \
                type [::aurig::core::util::_detect_type $ext] \
                lib  $lib \
                fullpath $full \
                relpath  [::aurig::core::util::_rel $full $root] \
                vhdl_std "" \
                srcset   $fsNameVal \
                origin   vivado \
                extra {}]
            dict set out f$idx $rec
            incr idx
        }
    }
    return $out
}
# --- Xilinx ISE .xise (XML) -------------------------------------------------
# Similar to .xpr but older format. Look for:
#   <file xil_pn:name="path/to/file.vhd" xil_pn:type="FILE_VHDL">
#     <association xil_pn:name="Implementation" xil_pn:seqID="123"/>
#   </file>
proc ::aurig::core::util::_collect_from_ise_xise {xisePath root} {
    # Backward compatibility: a relative -from path still resolves through
    # file normalize. Manifest-internal entries below use explicit project
    # directory anchoring via resolve_path.
    set projDir [file dirname [file normalize $xisePath]]
    if {$root eq ""} { set root $projDir }
    set f [open $xisePath r]; set xml [read $f]; close $f

    set out {}; set idx 0

    # ISE uses <file xil_pn:name="..." xil_pn:type="FILE_*">
    set fileRE {<file\s+xil_pn:name="([^"]+)"\s+xil_pn:type="([^"]+)"[^>]*>}

    set pos 0
    while {[regexp -indices -start $pos -nocase $fileRE $xml m fPath fType]} {
        set pos [lindex $m 1]
        set relPath [string range $xml [lindex $fPath 0] [lindex $fPath 1]]
        set fileType [string range $xml [lindex $fType 0] [lindex $fType 1]]

        # Convert ISE file types to our types
        set type "other"
        switch -glob -- $fileType {
            "FILE_VHDL"          { set type "vhdl" }
            "FILE_VERILOG"       { set type "verilog" }
            "FILE_SYSTEM_VERILOG" { set type "systemverilog" }
            "FILE_XCO"           { set type "xco" }
            "FILE_NGC"           { set type "ngc" }
            "FILE_UCF"           { set type "ucf" }
            "FILE_XDC"           { set type "xdc" }
            "FILE_TCL"           { set type "tcl" }
        }

        # Resolve path relative to project directory
        set full [::aurig::core::util::resolve_path $relPath $projDir]
        set ext [::aurig::core::util::_ext $full]

        set rec [dict create \
            name [file tail $full] \
            ext  $ext \
            type $type \
            lib  work \
            fullpath $full \
            relpath  [::aurig::core::util::_rel $full $root] \
            vhdl_std "" \
            srcset   implementation \
            origin   ise \
            extra [dict create ise_type $fileType]]
        dict set out f$idx $rec
        incr idx
    }
    return $out
}
# --- Quartus .qpf/.qsf -------------------------------------------------------
# .qpf doesn’t list files; .qsf (assignments) does:
#   set_global_assignment -name VHDL_FILE path/to/file.vhd
#   set_global_assignment -name VERILOG_FILE path/to/file.v
#   set_global_assignment -name SDC_FILE path/to/file.sdc
proc ::aurig::core::util::_collect_from_quartus {projPath root} {
    # Accept either .qsf or .qpf; if .qpf, locate a .qsf next to it
    # Backward compatibility: a relative -from path still resolves through
    # file normalize. QSF-internal entries below use explicit project
    # directory anchoring via resolve_path.
    set p    [file normalize $projPath]
    set dir  [file dirname $p]
    set base [file rootname [file tail $p]]
    set qsf  $p
    if {[string equal -nocase [file extension $p] ".qpf"]} {
        set cand [file join $dir "${base}.qsf"]
        if {[file exists $cand]} {
            set qsf $cand
        } else {
            if {![file isdirectory $dir]} {
                return {}
            }
            set list [glob -nocomplain -- [file join $dir *.qsf]]
            if {[llength $list] == 0} { return {} }
            set qsf [lindex $list 0]
        }
    }
    if {$root eq ""} { set root $dir }

    # --- whitelist of *_FILE assignment names we accept ---
    # Use list construction (no comments) so it's an even-length list.
    set mapList [list \
        VHDL_FILE           vhdl \
        VERILOG_FILE        verilog \
        SYSTEMVERILOG_FILE  systemverilog \
        SDC_FILE            sdc \
        QIP_FILE            qip \
        TCL_SCRIPT_FILE     tcl \
        QSYS_FILE           qsys \
        INC_FILE            inc \
    ]
    array set aType $mapList

    set f [open $qsf r]
    set txt [read $f]
    close $f

    set out {}; set idx 0
    foreach line [split $txt "\n"] {
        set s [string trim $line]
        if {$s eq ""} continue

        # Match: set_global_assignment -name <NAME> <VALUE...>
        if {![regexp {^set_global_assignment\s+-name\s+([A-Z_]+)\s+(.+)$} $s -> name path]} {
            continue
        }

        # Only accept whitelisted *_FILE names
        if {![info exists aType($name)]} {
            continue
        }
        set type $aType($name)

        # Extract value and unquote if needed
        set path [string trim $path]
        if {[string match "\"*\"" $path]} {
            set path [string range $path 1 end-1]
        }

        # Resolve relative to project dir
        set full $path
        if {![string equal [file pathtype $full] "absolute"]} {
            set full [::aurig::core::util::resolve_path $full $dir]
        }

        # Skip non-filelike entries (no extension)
        set ext [::aurig::core::util::_ext $full]
        if {$ext eq ""} continue

        set rec [dict create \
            name     [file tail $full] \
            ext      $ext \
            type     $type \
            lib      work \
            fullpath $full \
            relpath  [::aurig::core::util::_rel $full $root] \
            vhdl_std "" \
            srcset   assignments \
            origin   quartus \
            extra    [dict create qsf_name $name]]
        dict set out f$idx $rec
        incr idx
    }
    return $out
}


# --- Public API ---------------------------------------------------------------

# TCLLIB REQUIREMENT (F2/F3): the `yaml` format reads canonical-manifest-shaped
# project YAML and therefore REQUIRES tcllib `yaml`. When the resolved format is
# yaml and tcllib is absent, this call FAILS LOUDLY (via the schema guidance in
# _collect_from_yaml) -- it does NOT silently fall back to the readYamlMinimal
# lite parser, which cannot parse the multi-key file_sets/ip_cores list items.
# The ini / vivado / ise / quartus formats have no such requirement. Callers
# that may run without tcllib should detect absence (`catch {package require
# yaml}`) and skip/branch rather than invoke the yaml format blindly (see
# test/test_project_files_globstar.tcl for the skip pattern). This is a
# file-INVENTORY collector: it does NOT normalize/validate; canonical-manifest
# consumers needing that use ::aurig::core::schema::scan_project.
proc ::aurig::core::util::collect_project_files {args} {
    # -from <file>  (project.yaml | project.ini | project.xpr | project.xise | project.qpf/.qsf)
    # -format auto|yaml|ini|vivado|ise|quartus
    # -root <path>
    # -follow_globs 0|1 (YAML src expansion; other formats keep their behavior)
    # -report <varName> (optional caller variable; return shape is unchanged)
    # Report: declared_patterns and unmatched_patterns describe YAML src only;
    # unmatched_patterns is empty when globs are not expanded. total_files
    # counts final records. file_sets_present tests a top-level key, and
    # globs_unexpanded marks counts consumers must treat as unreliable.
    array set opt {-from {} -format auto -root {} -follow_globs 1 -report {}}

    if {[llength $args] % 2 != 0} {
        return -code error "usage: collect_project_files -from <file> ?-format auto|yaml|ini|vivado|ise|quartus? ?-root <path>? ?-follow_globs 1? ?-report <varName>?"
    }
    foreach {k v} $args {
        if {![info exists opt($k)]} { return -code error "invalid option $k" }
        set opt($k) $v
    }
    if {$opt(-from) eq ""} { return -code error "-from <file> is required" }

    set fmt $opt(-format)
    if {$fmt eq "auto"} {
        set ext [string tolower [file extension $opt(-from)]]
        switch -- $ext {
            ".yaml" { set fmt yaml }
            ".yml"  { set fmt yaml }
            ".ini"  { set fmt ini }
            ".xpr"  { set fmt vivado }
            ".xise" { set fmt ise }
            ".qpf"  { set fmt quartus }
            ".qsf"  { set fmt quartus }
            default {
                # fallback: sniff content
                set h [open $opt(-from) r]; set head [read $h 1024]; close $h
                if {[string match "*<Project*Vivado*" $head]} {
                    set fmt vivado
                } elseif {[string match "*<Project*ISE*" $head]} {
                    set fmt ise
                } elseif {[string match "*set_global_assignment*" $head]} {
                    set fmt quartus
                } elseif {[string match "*\[config\]*" [string tolower $head]]} {
                    set fmt ini
                } else {
                    set fmt yaml
                }
            }
        }
    }

    if {$opt(-report) ne ""} {
        set discovery [dict create declared_patterns {} unmatched_patterns {} file_sets_present 0]
        switch -- $fmt {
            yaml { set files [::aurig::core::util::_collect_from_yaml $opt(-from) $opt(-root) $opt(-follow_globs) discovery] }
            ini { set files [::aurig::core::util::_collect_from_ini $opt(-from) $opt(-root) discovery] }
            vivado { set files [::aurig::core::util::_collect_from_vivado_xpr $opt(-from) $opt(-root)] }
            ise { set files [::aurig::core::util::_collect_from_ise_xise $opt(-from) $opt(-root)] }
            quartus { set files [::aurig::core::util::_collect_from_quartus $opt(-from) $opt(-root)] }
            default { return -code error "unsupported format '$fmt'" }
        }
        set files [::aurig::core::util::_merge_sort_unique $files]
        # Board constraint records contribute to total_files, but their patterns
        # are excluded from declared_patterns and unmatched_patterns (src only).
        # Non-YAML formats have no declared src patterns: those fields stay empty.
        # The flag reflects the requested option, including formats that already
        # ignore it. Do not change their existing expansion behavior.
        # Canonical booleans and numeric values both have truth meaning to expr.
        # Values with no truth meaning leave the field empty (not measurable),
        # so paths that ignore this option continue to work.
        if {[string is boolean -strict $opt(-follow_globs)]
            || [string is double -strict $opt(-follow_globs)]} {
            set globs_unexpanded [expr {!$opt(-follow_globs)}]
        } else {
            set globs_unexpanded ""
        }
        upvar 1 $opt(-report) report
        set report [dict create \
            declared_patterns [dict get $discovery declared_patterns] \
            unmatched_patterns [dict get $discovery unmatched_patterns] \
            total_files [dict size $files] \
            file_sets_present [dict get $discovery file_sets_present] \
            globs_unexpanded $globs_unexpanded]
        return $files
    }

    switch -- $fmt {
        yaml   { return [::aurig::core::util::_merge_sort_unique [::aurig::core::util::_collect_from_yaml $opt(-from) $opt(-root) $opt(-follow_globs)]] }
        ini    { return [::aurig::core::util::_merge_sort_unique [::aurig::core::util::_collect_from_ini  $opt(-from) $opt(-root)]] }
        vivado { return [::aurig::core::util::_merge_sort_unique [::aurig::core::util::_collect_from_vivado_xpr $opt(-from) $opt(-root)]] }
        ise    { return [::aurig::core::util::_merge_sort_unique [::aurig::core::util::_collect_from_ise_xise $opt(-from) $opt(-root)]] }
        quartus { return [::aurig::core::util::_merge_sort_unique [::aurig::core::util::_collect_from_quartus $opt(-from) $opt(-root)]] }
        default { return -code error "unsupported format '$fmt'" }
    }
}

# Merge by fullpath (avoid duplicates if multiple sources referenced same file)
proc ::aurig::core::util::_merge_sort_unique {d} {
    # d: dict fN -> record
    # collapse duplicates by fullpath (first wins), then sort
    array set seen {}     ;# <<< make it an array

    set list {}
    foreach k [lsort -dict [dict keys $d]] {
        set rec [dict get $d $k]
        set fp  [dict get $rec fullpath]
        if {[info exists seen($fp)]} continue
        set seen($fp) 1
        lappend list $rec
    }

    # sort by relpath then name
    set list [lsort -command {apply {{a b} {
        set ar [dict get $a relpath]
        set br [dict get $b relpath]
        if {$ar eq $br} {
            return [string compare [dict get $a name] [dict get $b name]]
        }
        return [string compare $ar $br]
    }}} $list]

    # pack back into dict f0..fN
    set out {}; set i 0
    foreach rec $list {
        dict set out f$i $rec
        incr i
    }
    return $out
}
