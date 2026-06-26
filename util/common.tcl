# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Script Name  : common.tcl
# Namespace    : ::aurig::core::util
#-----------------------------------------------------------------------------
# Description: collection of utility procedures for the aurig package
#=============================================================================

namespace eval ::aurig::core::util {

    proc ::aurig::core::util::_is_repo_root {dir} {
        return [expr {
            [file exists [file join $dir init.tcl]] &&
            [file exists [file join $dir pkgIndex.tcl]] &&
            [file isdirectory [file join $dir analyze]]
        }]
    }

    proc ::aurig::core::util::_host_cwd_candidates {} {
        set candidates [list]

        if {[info exists ::env(PWD)] && $::env(PWD) ne ""} {
            lappend candidates [string map {\\ /} $::env(PWD)]
        }

        if {$::tcl_platform(platform) eq "windows"} {
            if {![catch {exec cmd /c cd} cwd] && $cwd ne ""} {
                lappend candidates [string map {\\ /} $cwd]
            }
        } else {
            if {![catch {exec /bin/pwd} cwd] && $cwd ne ""} {
                lappend candidates [string map {\\ /} $cwd]
            } elseif {![catch {exec pwd} cwd] && $cwd ne ""} {
                lappend candidates [string map {\\ /} $cwd]
            }
        }

        return $candidates
    }

    proc ::aurig::core::util::_absolutize_repo_root {dir} {
        if {[file pathtype $dir] eq "absolute"} {
            return $dir
        }

        foreach base [::aurig::core::util::_host_cwd_candidates] {
            if {$dir eq "."} {
                set candidate $base
            } else {
                set candidate [file join $base $dir]
            }
            if {[::aurig::core::util::_is_repo_root $candidate]} {
                return $candidate
            }
        }

        return $dir
    }

    proc ::aurig::core::util::find_repo_root {{start ""}} {
        if {$start eq ""} {
            error "find_repo_root requires a starting path (for example: \[file dirname \[info script\]\])"
        }

        set dir $start
        if {[file isfile $dir]} {
            set dir [file dirname $dir]
        }

        while {1} {
            if {[::aurig::core::util::_is_repo_root $dir]} {
                return [::aurig::core::util::_absolutize_repo_root $dir]
            }

            set parent [file dirname $dir]
            if {$parent eq $dir} {
                error "Could not find aurig repository root from: $start"
            }
            set dir $parent
        }
    }

    # Resolve a path against an explicit anchor directory.
    #
    # - If $path is absolute (file pathtype), return it as-is.
    # - If $path is relative, return [file join $anchor_dir $path].
    # - On Windows, volume-relative paths (C:foo, /foo without drive) are
    #   not supported as $path or as $anchor_dir; resolve_path raises an
    #   explicit error in both cases (anchor_dir validated up front,
    #   regardless of $path's pathtype). Callers that need such paths
    #   should canonicalize them first.
    # - Does NOT call [file normalize], does NOT consult [pwd] or any
    #   cwd-derived state. The returned path may contain "../" segments
    #   or other un-canonicalized forms; those are fully usable with
    #   [file join], [file exists], [open], [glob -- ...].
    #
    # - If $must_exist is true (default false) and the resolved path
    #   does not exist, raise an error with a clear message.
    #
    # Rationale: see PR #14 design notes. The whole point of this helper
    # is to avoid the [pwd]-corruption class of bugs that affected previous
    # PRs (#11, #12, #13). [file normalize] inside this proc would defeat
    # the purpose.
    proc ::aurig::core::util::resolve_path {path anchor_dir {must_exist 0}} {
        # Validate anchor_dir up front: volume-relative anchors are not
        # supported regardless of $path's pathtype. Even when $path is
        # absolute and anchor_dir is unused, accepting a malformed anchor
        # silently is misleading. The contract is that this proc anchors
        # paths against a directory; that directory must be valid.
        set anchor_ptype [file pathtype $anchor_dir]
        if {$anchor_ptype eq "volumerelative"} {
            error "resolve_path: anchor_dir is volume-relative (anchor_dir: $anchor_dir). Use an absolute or fully relative anchor."
        }

        set ptype [file pathtype $path]
        switch -- $ptype {
            absolute {
                set result $path
            }
            relative {
                set result [file join $anchor_dir $path]
            }
            volumerelative {
                error "resolve_path: volume-relative paths are not supported (path: $path). Use an absolute or fully relative path."
            }
            default {
                error "resolve_path: unknown path type '$ptype' (path: $path)"
            }
        }

        if {$must_exist && ![file exists $result]} {
            error "resolve_path: path does not exist: $result"
        }

        return $result
    }

    # `::aurig::core::util::_ini2dict` is the legacy compatibility shim
    # documented under README's "Legacy Compatibility" section. The
    # canonical INI parser lives in `util/ini_yaml.tcl` as
    # `::aurig::core::util::readIni` (see INI-DEBT-010 in
    # doc/developer/status.md). To keep `_ini2dict` callable for a
    # legacy script that sources ONLY `util/common.tcl` (i.e. without
    # going through init.tcl or sourcing `ini_yaml.tcl` first), the
    # shim defined here is lazy: on first call, if `readIni` is not
    # yet available it sources `ini_yaml.tcl` from the same directory.
    # `ini_yaml.tcl` itself re-defines `_ini2dict` as a direct one-
    # liner, so the second and subsequent calls go through that
    # version with no lazy-load overhead.
    # Anchor the sibling-file location absolutely at source time. The
    # caller may have invoked `source util/common.tcl` with a relative
    # path; resolving against the source-time `[pwd]` (which is what
    # `[file normalize]` does) freezes the directory NOW, so a later
    # `cd` by the caller before the first `_ini2dict` invocation does
    # not break the lazy `source [file join ... ini_yaml.tcl]`.
    variable _common_tcl_dir [file dirname [file normalize [info script]]]
    proc ::aurig::core::util::_ini2dict {ini_file {allow_append 1}} {
        variable _common_tcl_dir
        if {![llength [info commands ::aurig::core::util::readIni]]} {
            source [file join $_common_tcl_dir ini_yaml.tcl]
        }
        if {![llength [info commands ::aurig::core::util::readIni]]} {
            return -code error \
                "::aurig::core::util::_ini2dict: failed to load ::aurig::core::util::readIni from [file join $_common_tcl_dir ini_yaml.tcl]"
        }
        return [::aurig::core::util::readIni $ini_file]
    }

    # this procedure update the paths in a dict to be absolute
    # if they are relative. provide as argument also the base path to which
    # the relative paths are relative to.
    proc ::aurig::core::util::update_dict_paths {dictVarName basePath} {
        upvar 1 $dictVarName dict

        dict for {key value} $dict {
            if {$value eq "ignore"} {
                continue
            }

            # Coerce to list only if it REALLY is a Tcl list; otherwise wrap as one element
            if {[string is list -strict $value]} {
                set L $value
            } else {
                set L [list $value]
            }

            # Absolutize + normalize each element
            set out {}
            foreach p $L {
                if {$p eq ""} continue
                if {[file pathtype $p] ne "absolute"} {
                    set p [file normalize [file join $basePath $p]]
                } else {
                    set p [file normalize $p]
                }
                lappend out $p
            }

            # IMPORTANT: always store back a LIST (even if single element)
            dict set dict $key $out
        }
    }



    proc search_in_env {program} {
        set env_path [split $::env(PATH) ;]
        foreach line $env_path {
            if {[regexp {$program} $line]} {
                return line
            }
        }
    }

    proc file2string {inFile} {
        set fp [open $inFile r]
        set content [read $fp]
        return $content
    }

    proc find_vhdl_comment_index {line} {
        set in_quote 0
        set len [string length $line]
        for {set i 0} {$i < $len} {incr i} {
            set c [string index $line $i]
            if {$c eq "\""} {
                if {$in_quote && $i + 1 < $len && [string index $line [expr {$i + 1}]] eq "\""} {
                    incr i
                    continue
                }
                set in_quote [expr {!$in_quote}]
            } elseif {!$in_quote && $c eq "-" && $i+1 < $len && [string index $line [expr {$i+1}]] eq "-"} {
                return $i
            }
        }
        return -1
    }

    proc strip_vhdl_comment {line} {
        set idx [find_vhdl_comment_index $line]
        if {$idx < 0} {
            return [string trimright $line]
        }
        return [string trimright [string range $line 0 [expr {$idx - 1}]]]
    }

    # -- pdict
    #
    # Pretty print a dict similar to parray.
    #
    # USAGE:
    #
    #   pdict d [i [p [s]]]
    #
    # WHERE:
    #  d - dict value or reference to be printed
    #  i - indent level
    #  p - prefix string for one level of indent
    #  s - separator string between key and value
    #
    # EXAMPLE:
    # % set d [dict create a {1 i 2 j 3 k} b {x y z} c {i m j {q w e r} k o}]
    # a {1 i 2 j 3 k} b {x y z} c {i m j {q w e r} k o}
    # % pdict $d
    # a ->
    #   1 -> 'i'
    #   2 -> 'j'
    #   3 -> 'k'
    # b -> 'x y z'
    # c ->
    #   i -> 'm'
    #   j ->
    #     q -> 'w'
    #     e -> 'r'
    #   k -> 'o'
    # % pdict d
    # dict d
    # a ->
    # ...
    proc pdict { d {i 0} {p "  "} {s " -> "} } {
        set fRepExist [expr {0 < [llength\
                [info commands tcl::unsupported::representation]]}]
        if { (![string is list $d] || [llength $d] == 1)
                && [uplevel 1 [list info exists $d]] } {
            set dictName $d
            unset d
            upvar 1 $dictName d
            puts "dict $dictName"
        }
        if { ! [string is list $d] || [llength $d] % 2 != 0 } {
            return -code error  "error: pdict - argument is not a dict"
        }
        set prefix [string repeat $p $i]
        set max 0
        foreach key [dict keys $d] {
            if { [string length $key] > $max } {
                set max [string length $key]
            }
        }
        dict for {key val} ${d} {
            puts -nonewline "${prefix}[format "%-${max}s" $key]$s"
            if {    $fRepExist && [string match "value is a dict*"\
                        [tcl::unsupported::representation $val]]
                    || ! $fRepExist && [string is list $val]
                        && [llength $val] % 2 == 0 } {
                puts ""
                pdict $val [expr {$i+1}] $p $s
            } else {
                puts "'${val}'"
            }
        }
        return
    }

    proc guess_if_2008 {vhdFile} {
        # the procedure tries to recognize VHDL2008 constructs and return true if
        # VHDL 2008 construct were found, to pass the switch to the simulator
        set fp [open $vhdFile r]
        set content [read $fp]
        close $fp
        # split the line in multiple lines
        set records [split $content "\n"]
        foreach rec $records {
            # context
            if {[regexp {context} $rec]} {
                return true
            } elseif {[regexp {<<\s*[a-zA-Z0-9_\.]+\s*>>} $rec]} {
                # hierachical reference
                return true
            } elseif {[regexp {type\s+[a-zA-Z0-9_]+\s+is\s+array\s*(\s+natural\s+range\s+<\s*>\s*)\s*of\s+std_logic_vector\s*;} $rec]} {
                # unconstrained arrays
                return true
            }
        }
        return false
    }

    proc read_file {filename} {
        set fh [open $filename r]
        set content [read $fh]
        close $fh
        return $content
    }

    namespace export find_repo_root resolve_path _ini2dict update_dict_paths file2string search_in_env pdict guess_if_2008 read_file find_vhdl_comment_index strip_vhdl_comment


}
