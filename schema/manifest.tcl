# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# schema/manifest.tcl
# Namespace : ::aurig::core::schema
# Purpose   : AURIG project-manifest schema infrastructure for the
#             parser-class (lint/doc/analysis) consumer side.
#
#             This is the SINGLE home for manifest load + normalize + validate
#             in aurig-core. lint/doc/analysis consume the canonical view via
#             ::aurig::core::schema::scan_project; they must NOT re-implement
#             normalization or validation elsewhere.
#
# Pipeline (SAME order as aurig-build's resolve_manifest()):
#     read base  ->  deep-merge `.local` overlay
#                ->  normalize (legacy-alias rewrite, canonical v1)
#                ->  validate  (against the bundled manifest-v1.json)
#                ->  consume   (parser-class view + top name->file resolution)
#
# Authority: the canonical external contract is the JSON Schema
# `manifest-v1.json` vendored next to this file. It is byte-identical to
# aurig-build's source of truth at:
#     aurig-build/aurig_build/schema/manifest-v1.json
#
#   *** MANUAL CROSS-REPO PARITY GATE ***
#   There is no umbrella "schema home" repository yet, so cross-repo
#   byte-parity between this vendored copy and aurig-build's is a DOCUMENTED
#   MANUAL gate enforced at review time -- NOT automated CI. When aurig-build
#   bumps manifest-v1.json, re-vendor here (`cp` byte-for-byte) and update
#   `schema_sha256` below. The in-tree checksum guard
#   (verify_schema_checksum / the drift test) only protects against the
#   *local* vendored copy silently drifting; it cannot see aurig-build.
#
# PREREQUISITE: project-mode loading REQUIRES tcllib `yaml` and `json`.
#   - `yaml` : multi-key list items in file_sets/ip_cores (`- lib: work`
#              followed by sibling `src:`/`vhdl_std:`) are NOT parseable by
#              ::aurig::core::util::readYamlMinimal, so we do NOT fall back to it.
#   - `json` : the validator reads the bundled manifest-v1.json.
#   If either is absent, load FAILS LOUDLY with installation guidance.
#=============================================================================

namespace eval ::aurig::core::schema {
    namespace export \
        load_manifest scan_project \
        read_manifest normalize validate \
        require_libs schema_path verify_schema_checksum

    # Directory of this script; anchor for the bundled contract.
    variable _dir [file dirname [file normalize [info script]]]

    # Vendored canonical contract (byte-identical to aurig-build's copy).
    variable schema_file [file join $_dir manifest-v1.json]

    # Drift guard: SHA-256 of the byte-identical vendored manifest-v1.json.
    # If you re-vendor the schema, recompute and update this constant
    # (the drift test will otherwise fail). 7000 bytes, LF line endings.
    variable schema_sha256 \
        bcd8ebccd924a1c518e7c1e6f13944582ea628df5814e052e5399aee12207f5c

    # Cache of the parsed schema dict (per interpreter).
    variable _schema_cache ""
}

#-----------------------------------------------------------------------------
# Errors
#-----------------------------------------------------------------------------
# Raise a manifest error with `text` verbatim (the errorcode marks it as a
# schema/manifest failure). Callers reporting multiple lines join them
# themselves with [join $lines \n] -- this proc never re-splits its argument,
# so a single multi-word message is preserved as one line.
proc ::aurig::core::schema::_err {text} {
    return -code error -errorcode {AURIG SCHEMA MANIFEST} $text
}

#-----------------------------------------------------------------------------
# tcllib prerequisite. Fails LOUDLY; never silently degrades. `pkgs` defaults
# to the full project-mode set {yaml json}; pass a subset (e.g. {yaml}) for a
# path that needs only YAML parsing (the legacy file-inventory collector).
#-----------------------------------------------------------------------------
proc ::aurig::core::schema::require_libs {{pkgs {yaml json}}} {
    set missing {}
    foreach pkg $pkgs {
        if {[catch {package require $pkg}]} { lappend missing $pkg }
    }
    if {[llength $missing]} {
        set lines [list \
            "AURIG project-mode manifest loading requires the tcllib package(s): [join $missing {, }]." \
            "These are MANDATORY for project manifests and have no safe fallback:"]
        if {"yaml" in $missing} {
            lappend lines \
                "  - yaml: file_sets/ip_cores use multi-key YAML list items that" \
                "          ::aurig::core::util::readYamlMinimal cannot parse; falling back" \
                "          to it would silently mis-read the manifest."
        }
        if {"json" in $missing} {
            lappend lines \
                "  - json: the schema validator reads the bundled manifest-v1.json."
        }
        lappend lines \
            "Install tcllib and ensure it is on the Tcl auto_path, e.g.:" \
            "  Debian/Ubuntu : sudo apt-get install tcllib" \
            "  other/Windows : see the Requirements section of this project's README." \
            "  from source   : add the tcllib directory to \$auto_path."
        ::aurig::core::schema::_err [join $lines "\n"]
    }
}

#-----------------------------------------------------------------------------
# Structural helpers (Tcl has no native dict/list/scalar type tags; YAML->Tcl
# is lossy -- booleans become 0/1, empty map and empty list both become "",
# and an integer and its string spelling are indistinguishable). These
# heuristics are tuned to the manifest's shape and documented where they bite.
#-----------------------------------------------------------------------------

# A value is treated as a MAPPING when it is an even-length list whose
# even-position elements all look like YAML mapping keys (identifiers).
# A list of scalars (paths contain "/", "." or are odd-length) or a list of
# sub-maps (elements carry spaces/braces) therefore reads as NOT-a-map, which
# is exactly what the deep-merge and validator want.
proc ::aurig::core::schema::_is_map {v} {
    if {[catch {llength $v} n]} { return 0 }
    if {$n == 0 || ($n % 2) != 0} { return 0 }
    foreach {k _} $v {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $k]} { return 0 }
    }
    return 1
}

# Empty per the overlay merge spec: empty string, or an empty list/map.
#
# FORCED DIVERGENCE (F4) -- the spec says "null REPLACE, empty/missing IGNORE".
# That is UNIMPLEMENTABLE in Tcl: tcllib's yaml collapses YAML `null`, ``, `[]`
# and `{}` all to the SAME Tcl value (the empty string ""). Core therefore
# cannot tell an explicit `null` (which the spec says should REPLACE the base)
# from an empty/absent value (which the spec says to IGNORE). Core resolves the
# collision ONE way: null == empty == IGNORE (base retained). So an overlay
# cannot blank out a base key by setting it to null/empty here.
# (Conversely, aurig-build run.py's _deep_merge REPLACES on empties, violating
# the spec's "empty ignored" clause.) Both are tracked as a spec-reconciliation
# debt row in doc/developer/status.md (SCHEMA-DEBT-OVERLAY-NULL).
proc ::aurig::core::schema::_is_empty {v} {
    if {$v eq ""} { return 1 }
    if {![catch {llength $v} n] && $n == 0} { return 1 }
    return 0
}

#-----------------------------------------------------------------------------
# `.local` overlay
#-----------------------------------------------------------------------------
# Sibling overlay path: project.yaml -> project.local.yaml (extension follows
# the base). OS-independent: built with file ops, no separator assumptions.
proc ::aurig::core::schema::_overlay_path {base} {
    set dir  [file dirname $base]
    set ext  [file extension $base]
    set stem [file rootname [file tail $base]]
    return [file join $dir "${stem}.local${ext}"]
}

# Deep merge per the agreed spec (matches aurig-build's _deep_merge):
#   - dict + dict        -> recurse
#   - list/scalar        -> overlay REPLACES base
#   - overlay empty/miss -> IGNORED (base retained)
# `out`/`overlay` are values, not mutated in place; a new dict is returned.
proc ::aurig::core::schema::_deep_merge {base overlay} {
    set out $base
    foreach {k ov} $overlay {
        if {[::aurig::core::schema::_is_empty $ov]} { continue }
        if {[dict exists $out $k]} {
            set bv [dict get $out $k]
            if {[::aurig::core::schema::_is_map $bv] && [::aurig::core::schema::_is_map $ov]} {
                dict set out $k [::aurig::core::schema::_deep_merge $bv $ov]
                continue
            }
        }
        dict set out $k $ov
    }
    return $out
}

#-----------------------------------------------------------------------------
# YAML read (tcllib `yaml` ONLY -- never readYamlMinimal)
#-----------------------------------------------------------------------------
proc ::aurig::core::schema::_read_yaml_file {path} {
    if {[string index $path 0] eq "|"} {
        ::aurig::core::schema::_err "manifest path must not start with '|': $path"
    }
    if {![file isfile $path]} {
        ::aurig::core::schema::_err "manifest file not found or not a regular file: $path"
    }
    # Route through the pre-flight so a direct caller of _read_yaml_file gets
    # the same tcllib guidance as read_manifest / load_manifest; there is no
    # readYamlMinimal fallback on the project-mode path.
    ::aurig::core::schema::require_libs yaml
    set f [open $path r]
    set txt [read $f]
    close $f
    set d [::yaml::yaml2dict $txt]
    if {$d eq ""} { return [dict create] }
    # Accept any dict-usable top level (even-length list). We use `dict size`
    # rather than `_is_map` so a manifest carrying a non-identifier key such as
    # `$schema` (a common JSON-schema convenience key) or any future key is NOT
    # rejected here -- it loads and surfaces as an unknown-key WARNING during
    # validation. Only a non-mapping top level (odd-length / unbalanced) fails.
    if {[catch {dict size $d}]} {
        ::aurig::core::schema::_err "manifest top level must be a YAML mapping: $path"
    }
    return $d
}

# Read base manifest and deep-merge a sibling `.local` overlay if present.
proc ::aurig::core::schema::read_manifest {path} {
    ::aurig::core::schema::require_libs
    set cfg [::aurig::core::schema::_read_yaml_file $path]
    set ovl [::aurig::core::schema::_overlay_path $path]
    if {[file isfile $ovl]} {
        set overlay [::aurig::core::schema::_read_yaml_file $ovl]
        if {![::aurig::core::schema::_is_empty $overlay]} {
            set cfg [::aurig::core::schema::_deep_merge $cfg $overlay]
        }
    }
    return $cfg
}

#=============================================================================
# normalize  --  legacy-alias rewrite to canonical v1
#
# Faithful Tcl port of aurig-build/aurig_build/schema/normalize.py, SAME order.
# Returns {canonicalCfg warningsList}. Idempotent and OS-independent.
#
# DEFERRED to PR-B (NOT done here): device.vendor inference from
# tool.synth.kind, and ip_cores black-box cracking. aurig-build's normalize
# does neither either, so this port stays faithful by omission.
#=============================================================================
proc ::aurig::core::schema::normalize {cfg} {
    set warns {}
    ::aurig::core::schema::_norm_schema_version cfg
    ::aurig::core::schema::_norm_top              cfg warns
    ::aurig::core::schema::_norm_tool             cfg warns
    ::aurig::core::schema::_norm_device           cfg warns
    ::aurig::core::schema::_norm_board_filesets   cfg warns
    ::aurig::core::schema::_norm_libraries        cfg warns
    ::aurig::core::schema::_norm_env_generics     cfg warns
    ::aurig::core::schema::_norm_sim              cfg warns
    ::aurig::core::schema::_norm_quartus_features cfg warns
    ::aurig::core::schema::_coerce_vhdl_std       cfg
    return [list $cfg $warns]
}

proc ::aurig::core::schema::_warn {warnsVar msg} {
    upvar 1 $warnsVar warns
    lappend warns "\[WARN\] $msg"
}

# "1.0"/"1.0.0" -> "1" (silent producer-format tolerance; "1" untouched;
# a real future minor like "1.2" is left intact so the pattern rejects it).
proc ::aurig::core::schema::_norm_schema_version {cfgVar} {
    upvar 1 $cfgVar cfg
    if {![dict exists $cfg schema_version]} return
    set sv [dict get $cfg schema_version]
    if {[regexp {^1(\.0){1,2}$} $sv]} {
        dict set cfg schema_version "1"
    }
}

proc ::aurig::core::schema::_is_path_form {top} {
    if {[string match {*/*} $top] || [string match "*\\*" $top]} { return 1 }
    set lower [string tolower $top]
    foreach e {.vhd .vhdl .v .sv .vh .svh} {
        if {[string match "*$e" $lower]} { return 1 }
    }
    return 0
}

# Path-form `top` -> entity-name `top` + `top_file`.
proc ::aurig::core::schema::_norm_top {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    if {![dict exists $cfg top]} return
    set top [dict get $cfg top]
    if {![::aurig::core::schema::_is_path_form $top]} return
    set norm [string map {\\ /} $top]
    set base [lindex [split $norm /] end]
    if {[string first . $base] >= 0} {
        set stem [file rootname $base]
    } else {
        set stem $base
    }
    if {![dict exists $cfg top_file]} { dict set cfg top_file $top }
    dict set cfg top $stem
    ::aurig::core::schema::_warn warns \
        "top: path form '$top' is deprecated; set 'top' to the real entity/module\
 name (guessed '$stem' from the file name) and keep the path in 'top_file'."
}

# Bare string -> {linux <v> windows <v>} OS-keyed object.
#
# Python (normalize.py:_os_keyify) converts ONLY when the value isinstance str.
# Tcl parity (F5): convert only a BARE SCALAR -- not a map (already an OS-keyed
# object) and not a multi-element sequence. A single-token value (llength <= 1)
# is unambiguously a bare scalar and is converted; a value with llength > 1 is
# left untouched, because Tcl cannot distinguish a YAML sequence (e.g.
# `env_script: [a, b]`, which Python would NOT wrap) from a bare scalar string
# that merely contains spaces (e.g. an unquoted `C:/Program Files/...` path,
# which Python WOULD wrap). We err toward NOT mangling a sequence; the spaced
# bare-string case is left for the schema validator to reject as a type
# mismatch, and is enumerated in the divergence envelope (status.md). tool.* is
# metadata the parser-class consumer ignores, so this is low-stakes.
proc ::aurig::core::schema::_os_keyify {parentVar key ctx warnsVar} {
    upvar 1 $parentVar parent $warnsVar warns
    if {![dict exists $parent $key]} return
    set val [dict get $parent $key]
    if {[::aurig::core::schema::_is_map $val]} return
    if {[::aurig::core::schema::_is_empty $val]} return
    if {[catch {llength $val} n] || $n > 1} return
    dict set parent $key [dict create linux $val windows $val]
    ::aurig::core::schema::_warn warns \
        "$ctx.$key: bare string is deprecated; use an OS-keyed object {linux,\
 windows}. Applied to BOTH keys -- set them explicitly to resolve the OS\
 ambiguity."
}

proc ::aurig::core::schema::_norm_tool {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    if {![dict exists $cfg tool]} return
    set tool [dict get $cfg tool]
    if {![::aurig::core::schema::_is_map $tool]} return

    if {[dict exists $tool synth] && [::aurig::core::schema::_is_map [dict get $tool synth]]} {
        set synth [dict get $tool synth]
        if {[dict exists $synth kind]} {
            set kind [dict get $synth kind]
            if {$kind in {ise precision libero}} {
                ::aurig::core::schema::_err \
                    "tool.synth.kind: '$kind' is removed and has no canonical\
 backend. Supported: vivado, quartus, diamond, radiant."
            }
        }
        ::aurig::core::schema::_os_keyify synth env_script "tool.synth" warns
        ::aurig::core::schema::_os_keyify synth bin_dir    "tool.synth" warns
        dict set tool synth $synth
    }

    if {[dict exists $tool sim] && [::aurig::core::schema::_is_map [dict get $tool sim]]} {
        set sim [dict get $tool sim]
        ::aurig::core::schema::_norm_sim_engine sim warns
        ::aurig::core::schema::_os_keyify sim env_script "tool.sim" warns
        ::aurig::core::schema::_os_keyify sim bin_dir    "tool.sim" warns
        dict set tool sim $sim
    }
    dict set cfg tool $tool
}

proc ::aurig::core::schema::_norm_sim_engine {simVar warnsVar} {
    upvar 1 $simVar sim $warnsVar warns
    if {![dict exists $sim kind]} return
    set kind [dict get $sim kind]
    if {$kind eq "isim"} {
        ::aurig::core::schema::_err \
            "tool.sim.kind: 'isim' is removed and has no canonical target. Use a\
 supported engine (ghdl, nvc, modelsim, questa, active-hdl, xsim)."
    }
    if {$kind eq "vunit"} {
        dict unset sim kind
        dict set sim framework vunit
        ::aurig::core::schema::_warn warns \
            "tool.sim.kind: 'vunit' is deprecated; set 'tool.sim.framework:\
 vunit' instead (engine left unset)."
        return
    }
    set remap [dict create questasim questa vivado xsim]
    if {[dict exists $remap $kind]} {
        set canon [dict get $remap $kind]
        dict set sim kind $canon
        if {![dict exists $sim framework]} { dict set sim framework direct }
        ::aurig::core::schema::_warn warns \
            "tool.sim.kind: '$kind' is deprecated; use framework: direct with\
 kind: $canon."
        return
    }
    if {![dict exists $sim framework]} {
        dict set sim framework direct
        ::aurig::core::schema::_warn warns \
            "tool.sim.kind: '$kind' without a framework is deprecated; set\
 'tool.sim.framework: direct' explicitly."
    }
}

# altera->intel, microsemi->microchip; device.speed is a hard error.
proc ::aurig::core::schema::_norm_device {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    if {![dict exists $cfg device]} return
    set device [dict get $cfg device]
    if {![::aurig::core::schema::_is_map $device]} return
    set vendor [expr {[dict exists $device vendor] ? [dict get $device vendor] : ""}]
    set remap [dict create altera intel microsemi microchip]
    if {$vendor ne "" && [dict exists $remap $vendor]} {
        set canon [dict get $remap $vendor]
        dict set device vendor $canon
        ::aurig::core::schema::_warn warns \
            "device.vendor: '$vendor' is deprecated; use '$canon'."
        set vendor $canon
    }
    if {[dict exists $device speed]} {
        ::aurig::core::schema::_err \
            "device.speed is deprecated and the speed-grade position inside a\
 part string is vendor-specific and not safely derivable (vendor='$vendor').\
 Embed the speed grade directly into device.part (e.g. xilinx\
 'xc7a100t-1csg324') and remove device.speed."
    }
    dict set cfg device $device
}

proc ::aurig::core::schema::_norm_board_filesets {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    if {![dict exists $cfg file_sets]} return
    set fs [dict get $cfg file_sets]
    if {![::aurig::core::schema::_is_map $fs]} return

    if {[dict exists $fs ip]} {
        set ip [dict get $fs ip]
        dict unset fs ip
        set rtl [expr {[dict exists $fs rtl] ? [dict get $fs rtl] : {}}]
        foreach e $ip { lappend rtl $e }
        dict set fs rtl $rtl
        ::aurig::core::schema::_warn warns \
            "file_sets.ip is deprecated; pre-generated IP HDL is plain RTL --\
 moved into file_sets.rtl."
    }
    dict set cfg file_sets $fs

    if {[dict exists $fs constraints]} {
        set constraints [dict get $fs constraints]
        dict unset fs constraints
        dict set cfg file_sets $fs
        ::aurig::core::schema::_route_constraints cfg $constraints warns
    }
}

proc ::aurig::core::schema::_route_constraints {cfgVar constraints warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    # Python (normalize.py:_route_constraints) requires a real list (isinstance
    # list) and raises otherwise. Tcl parity (F5): a MAPPING supplied here is
    # unambiguously NOT a sequence -> reject. A bare-string-vs-list-of-one
    # (e.g. `constraints: pins.xdc`) is UNDECIDABLE in Tcl (both are a 1-element
    # list), so we do NOT reject it -- it migrates as a single entry. That
    # ambiguity is enumerated in the divergence envelope (status.md).
    if {[::aurig::core::schema::_is_map $constraints]} {
        ::aurig::core::schema::_err \
            "file_sets.constraints must be a list (sequence) of constraint files\
 to migrate to board.{xdc,sdc,lpf,pdc}_files, not a mapping."
    }
    if {![string is list $constraints]} {
        ::aurig::core::schema::_err \
            "file_sets.constraints must be a list of constraint files to migrate\
 to board.{xdc,sdc,lpf,pdc}_files."
    }
    set board [expr {[dict exists $cfg board] ? [dict get $cfg board] : {}}]
    set map [dict create .xdc xdc_files .sdc sdc_files .lpf lpf_files .pdc pdc_files]
    foreach path $constraints {
        set ext ""
        if {[string first . $path] >= 0} { set ext [string tolower [file extension $path]] }
        if {$ext eq ".ucf"} {
            ::aurig::core::schema::_err \
                "file_sets.constraints entry '$path': UCF constraints are removed\
 (no canonical target)."
        }
        if {![dict exists $map $ext]} {
            ::aurig::core::schema::_err \
                "file_sets.constraints entry '$path': cannot route by extension;\
 place it under the matching board.<type>_files."
        }
        set target [dict get $map $ext]
        set cur [expr {[dict exists $board $target] ? [dict get $board $target] : {}}]
        lappend cur $path
        dict set board $target $cur
    }
    dict set cfg board $board
    ::aurig::core::schema::_warn warns \
        "file_sets.constraints is deprecated; routed to\
 board.{xdc,sdc,lpf,pdc}_files by file extension."
}

# THE atomic rename: `libraries` -> `external_libraries`. Existing
# external_libraries keys win (setdefault semantics).
proc ::aurig::core::schema::_norm_libraries {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    if {![dict exists $cfg libraries]} return
    set legacy [dict get $cfg libraries]
    dict unset cfg libraries
    set ext [expr {[dict exists $cfg external_libraries] ? [dict get $cfg external_libraries] : {}}]
    if {[::aurig::core::schema::_is_map $legacy]} {
        foreach {k v} $legacy {
            if {![dict exists $ext $k]} { dict set ext $k $v }
        }
    }
    dict set cfg external_libraries $ext
    ::aurig::core::schema::_warn warns \
        "libraries is deprecated; renamed to external_libraries."
}

proc ::aurig::core::schema::_norm_env_generics {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    if {![dict exists $cfg env]} return
    set env [dict get $cfg env]
    if {![::aurig::core::schema::_is_map $env] || ![dict exists $env generics]} return
    set legacy [dict get $env generics]
    dict unset env generics
    dict set cfg env $env
    if {[::aurig::core::schema::_is_map $legacy]} {
        set gen [expr {[dict exists $cfg generics] ? [dict get $cfg generics] : {}}]
        foreach {k v} $legacy {
            if {![dict exists $gen $k]} { dict set gen $k $v }
        }
        dict set cfg generics $gen
    }
    ::aurig::core::schema::_warn warns \
        "env.generics is deprecated; moved to top-level generics."
}

proc ::aurig::core::schema::_norm_sim {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns
    if {![dict exists $cfg sim]} return
    set sim [dict get $cfg sim]
    if {![::aurig::core::schema::_is_map $sim]} return

    if {[dict exists $sim top_tb]} {
        set v [dict get $sim top_tb]
        dict unset sim top_tb
        if {![dict exists $sim default_top_tb]} { dict set sim default_top_tb $v }
        ::aurig::core::schema::_warn warns \
            "sim.top_tb is deprecated; renamed to sim.default_top_tb."
    }
    if {[dict exists $sim sim_options]} {
        set v [dict get $sim sim_options]
        dict unset sim sim_options
        if {![dict exists $sim options]} { dict set sim options $v }
        ::aurig::core::schema::_warn warns \
            "sim.sim_options is deprecated; renamed to sim.options."
    }

    set tb_lib [expr {[dict exists $sim tb_lib] ? [dict get $sim tb_lib] : ""}]

    if {[dict exists $sim tb_folder]} {
        set folder [string trimright [string map {\\ /} [dict get $sim tb_folder]] /]
        dict unset sim tb_folder
        set lib [expr {$tb_lib ne "" ? $tb_lib : "tb"}]
        set fs [expr {[dict exists $cfg file_sets] ? [dict get $cfg file_sets] : {}}]
        set simset [expr {[dict exists $fs sim] ? [dict get $fs sim] : {}}]
        set srcs {}
        foreach e {.vhd .vhdl .v .sv} { lappend srcs "$folder/**/*$e" }
        lappend simset [dict create lib $lib src $srcs]
        dict set fs sim $simset
        dict set cfg file_sets $fs
        ::aurig::core::schema::_warn warns \
            "sim.tb_folder is deprecated; converted to a file_sets.sim entry\
 (lib='$lib') with HDL globs under '$folder'."
    }

    if {[dict exists $sim tb_lib]} {
        dict unset sim tb_lib
        if {[dict exists $sim default_top_tb]} {
            set dtb [dict get $sim default_top_tb]
            if {$dtb ne "" && [string first . $dtb] < 0 && $tb_lib ne ""} {
                dict set sim default_top_tb "$tb_lib.$dtb"
            }
        }
        ::aurig::core::schema::_warn warns \
            "sim.tb_lib is deprecated; fold the library into a qualified\
 sim.default_top_tb (<lib>.<tb>) or file_sets.sim\[\].lib."
    }
    dict set cfg sim $sim
}

proc ::aurig::core::schema::_norm_quartus_features {cfgVar warnsVar} {
    upvar 1 $cfgVar cfg $warnsVar warns

    if {[dict exists $cfg quartus] && [::aurig::core::schema::_is_map [dict get $cfg quartus]]} {
        set quartus [dict get $cfg quartus]
        if {[dict exists $quartus qip_files]} {
            set qips [dict get $quartus qip_files]
            dict unset quartus qip_files
            set ipc [expr {[dict exists $cfg ip_cores] ? [dict get $cfg ip_cores] : {}}]
            foreach src $qips { lappend ipc [dict create kind qip src $src] }
            dict set cfg ip_cores $ipc
            dict set cfg quartus $quartus
            ::aurig::core::schema::_warn warns \
                "quartus.qip_files is deprecated; converted to ip_cores entries\
 with kind: qip."
        }
    }

    if {[dict exists $cfg features] && [::aurig::core::schema::_is_map [dict get $cfg features]]} {
        set features [dict get $cfg features]
        if {[dict exists $features block_design]} {
            set bd [dict get $features block_design]
            dict unset features block_design
            if {[::aurig::core::schema::_is_map $bd] && [dict exists $bd enabled] \
                    && [dict get $bd enabled] in {1 true True}} {
                set src ""
                if {[dict exists $bd tcl]} { set src [dict get $bd tcl] }
                if {$src eq "" && [dict exists $bd src]} { set src [dict get $bd src] }
                if {$src eq ""} {
                    ::aurig::core::schema::_err \
                        "features.block_design is enabled but has no 'tcl'/'src'\
 generator script to migrate to ip_cores."
                }
                set ipc [expr {[dict exists $cfg ip_cores] ? [dict get $cfg ip_cores] : {}}]
                lappend ipc [dict create kind bd src $src]
                dict set cfg ip_cores $ipc
                ::aurig::core::schema::_warn warns \
                    "features.block_design is deprecated; converted to an\
 ip_cores entry with kind: bd."
            } else {
                ::aurig::core::schema::_warn warns \
                    "features.block_design is deprecated and was disabled\
 (enabled not true); dropped."
            }
            if {[::aurig::core::schema::_is_empty $features]} {
                dict unset cfg features
            } else {
                dict set cfg features $features
            }
        }
    }
}

# int vhdl_std -> string. In Tcl from YAML these are already strings, so this
# is effectively a normalization-of-record (canonical written form is string)
# and a no-op on value; kept for parity / idempotence.
proc ::aurig::core::schema::_coerce_vhdl_std {cfgVar} {
    upvar 1 $cfgVar cfg
    if {![dict exists $cfg file_sets]} return
    set fs [dict get $cfg file_sets]
    if {![::aurig::core::schema::_is_map $fs]} return
    foreach group {rtl sim} {
        if {![dict exists $fs $group]} continue
        set entries [dict get $fs $group]
        set out {}
        foreach e $entries {
            if {[::aurig::core::schema::_is_map $e] && [dict exists $e vhdl_std]} {
                set vs [dict get $e vhdl_std]
                if {[string is integer -strict $vs]} {
                    dict set e vhdl_std [string trim $vs]
                }
            }
            lappend out $e
        }
        dict set fs $group $out
    }
    dict set cfg file_sets $fs
}

#=============================================================================
# validate  --  hand-rolled validator against the bundled manifest-v1.json
#
# Faithful port of aurig-build/aurig_build/schema/validate.py, adapted for the
# lossy YAML->Tcl model. ENFORCED exactly as in aurig-build:
#   required / enum / const / pattern / minLength / minItems / items /
#   properties / additionalProperties / $ref / allOf / if-then-else / not.
# Structural discrimination Tcl CAN do and DOES enforce:
#   - required-key enforcement on objects: `{}` / `device: {}` / `tool.synth: {}`
#     are validated AS (empty) objects, so their required keys are reported
#     missing (they FAIL). Keyed on schema intent + `dict size`, so a mapping
#     with non-identifier keys (`$schema`, future keys) is still an object.
#   - an odd-length / unbalanced value where an object is required is provably
#     NOT a mapping -> type error.
#   - decidable VALUE constraints (enum / const / pattern / minLength /
#     minItems) run regardless of the scalar-typing leniency below.
# Option A: core `validate` is a LENIENT consumption safety-net and must NEVER
# false-reject valid input. The authoritative strict (real-typed) validator is
# aurig-build's, in the pipeline.
#
# DIVERGENCE ENVELOPE -- the FULL enumerated set of inputs this validator does
# NOT reject but the Python (real-typed) validator WOULD. Each is a genuine
# YAML->Tcl information loss (tcllib yaml erases the distinction), NOT a
# shortcut. Mirrored in doc/developer/status.md (SCHEMA-DEBT-VALIDATOR-ENVELOPE):
#   1. scalar vs 1-element sequence: `board.xdc_files: pins.xdc` (bare scalar) is
#      accepted as if `[pins.xdc]`. Python requires an array. (Both are a
#      1-element Tcl list; indistinguishable.)
#   2. SCALAR TYPE is never enforced (string/integer/number/boolean all accept
#      ANY value) -- the single root cause consolidating the former separate
#      int/string, bool/0-1, number, and multi-word-string items. A value YAML-
#      collapsed into a list/map shape (e.g. the multi-word strings "Foo Bar",
#      "Artix 7", "fast mode") is a VALID scalar that `_is_map`/`string is
#      entier` would mis-judge, so any per-scalar shape check here only ever
#      false-rejected. Decidable value constraints (enum/const/pattern/minLength)
#      still apply -- e.g. `vhdl_std` is policed by its `oneOf` enums (evaluated
#      "AT LEAST one branch matches", since the string-enum and int-enum branches
#      cover the SAME value set and are type-indistinguishable here), and
#      `schema_version` by its pattern. Strict scalar typing is aurig-build's.
#   3. null vs empty vs []/{} vs "": all collapse to the empty string, so an
#      empty value satisfies `object` (empty object), `array` (empty array) and
#      `null` alike; only NON-empty structural mismatches are caught.
#   4. mapping supplied where an ARRAY is required: NOT rejected. A 2-element
#      list of filename-like strings (e.g. `board.xdc_files: [pins.xdc,
#      timing.xdc]`, `file_sets.rtl[].src: [alu.vhd, top.vhd]`) is
#      indistinguishable in Tcl from a 1-pair dict, so core accepts any
#      list-shaped value as an array. A genuine mapping-where-array error
#      surfaces at consumption (`_collect_fileset` finds no entries) or via
#      aurig-build. (Fixes the round-1 false-reject of multi-file src/xdc lists.)
#   5. array ITEMS of a map-looking array are NOT validated: when a list LOOKS
#      like a 1-pair dict (`_is_map` true, e.g. [pins.xdc timing.xdc]) the
#      per-item `items` checks are skipped (we cannot tell elements from k/v
#      pairs, and forcing it would reintroduce the discrimination problem and
#      still couldn't reject under lenient scalars). Lists of multi-key objects
#      (elements carry spaces -> NOT map-looking, e.g. file_sets.rtl entries)
#      ARE item-validated, so their required keys are still enforced. The
#      authoritative item check is aurig-build's. (NOTE: `minItems` is a
#      DECIDABLE count and DOES fire here regardless of `_is_map` -- only the
#      per-element `items` check is skipped.)
#   6. an even-token scalar / sequence is accepted where an OBJECT is required:
#      object detection uses `dict size` (the only decidable structural test
#      under type-collapse), so any even-length token list satisfies it and is
#      read as a key/value mapping. So `device: "vendor xilinx family artix7
#      part xc7a"` (a 6-token scalar) loads as a valid required-key object, and a
#      top-level YAML SEQUENCE of even, key-like tokens loads as a manifest. An
#      ODD-length / unbalanced value is still provably-not-a-mapping and IS
#      rejected. Python (real-typed) distinguishes str/list from dict and would
#      reject these; core cannot, and defers to aurig-build's strict validator.
#=============================================================================
proc ::aurig::core::schema::schema_path {} {
    variable schema_file
    return $schema_file
}

proc ::aurig::core::schema::_load_schema {} {
    variable _schema_cache
    variable schema_file
    if {$_schema_cache ne ""} { return $_schema_cache }
    ::aurig::core::schema::require_libs json
    set f [open $schema_file r]
    set txt [read $f]
    close $f
    set _schema_cache [::json::json2dict $txt]
    return $_schema_cache
}

proc ::aurig::core::schema::_resolve {schema defs} {
    if {[dict exists $schema {$ref}]} {
        set ref [dict get $schema {$ref}]
        set prefix "#/\$defs/"
        if {[string match "#/\$defs/*" $ref]} {
            set name [string range $ref [string length $prefix] end]
            if {[dict exists $defs $name]} { return [dict get $defs $name] }
        }
    }
    return $schema
}

proc ::aurig::core::schema::_type_ok {value type_spec} {
    set types [expr {[::aurig::core::schema::_is_scalar_typelist $type_spec] ? $type_spec : [list $type_spec]}]
    foreach t $types {
        if {[::aurig::core::schema::_type_one $value $t]} { return 1 }
    }
    return 0
}

# A JSON "type" spec is either a single string ("object") or a JSON array of
# strings (["string","integer"]). After json2dict both are Tcl lists; we treat
# it as a multi-type list when every element is a known type keyword.
proc ::aurig::core::schema::_is_scalar_typelist {spec} {
    if {[llength $spec] < 2} { return 0 }
    foreach t $spec {
        if {$t ni {object array string boolean integer number null}} { return 0 }
    }
    return 1
}

# Does this (resolved) schema describe an object? Used so that an EMPTY value
# ("") is still validated against the object SHAPE the schema expects -- its
# required-key check runs for an empty object (`{}`, `device: {}`,
# `tool.synth: {}`) rather than silently slipping through.
proc ::aurig::core::schema::_schema_expects_object {schema} {
    if {[dict exists $schema required]} { return 1 }
    if {[dict exists $schema properties]} { return 1 }
    if {[dict exists $schema additionalProperties]} { return 1 }
    if {[dict exists $schema type]} {
        if {"object" in [dict get $schema type]} { return 1 }
    }
    return 0
}

# Type acceptance under the LENIENT model (round-3 root-cause fix). A
# type-collapsed YAML value (post yaml2dict) can be a scalar, a list, or a dict
# that are mutually indistinguishable in Tcl, so a type check may only REJECT
# when the mismatch is DECIDABLE. The decidable structural facts are:
#   - object: a value is dict-usable iff `dict size` succeeds (even-length list,
#     or empty). An odd-length / unbalanced value is provably NOT a mapping ->
#     rejected. `dict size` (not `_is_map`) is used so a mapping with non-
#     identifier keys ($schema, future keys) is still recognised as an object.
#   - array: any value with a well-formed `llength` is accepted (everything that
#     is a valid Tcl list -- which under type-collapse is the only decidable
#     fact; a mapping-looking 2-element list is accepted, see envelope item 4).
# SCALAR types (string/integer/number/boolean) accept ANY value: a valid scalar
# such as a multi-word string ("Foo Bar", "Artix 7", "fast mode") is collapsed
# into something `_is_map`/`string is entier` would mis-judge, so per-scalar
# shape checks here only ever produced FALSE-REJECTS. Value-level constraints
# that ARE decidable (enum / const / pattern / minLength) still run in
# `_validate` and remain enforced; strict scalar typing is aurig-build's job.
proc ::aurig::core::schema::_type_one {value t} {
    switch -- $t {
        object  { return [expr {![catch {dict size $value}]}] }
        array   { return [expr {![catch {llength $value}]}] }
        null    { return [expr {$value eq ""}] }
        string  -
        integer -
        number  -
        boolean { return 1 }
        default { return 1 }
    }
}

proc ::aurig::core::schema::_known_props {schema defs} {
    set schema [::aurig::core::schema::_resolve $schema $defs]
    set props {}
    if {[dict exists $schema properties]} {
        foreach k [dict keys [dict get $schema properties]] { lappend props $k }
    }
    if {[dict exists $schema allOf]} {
        foreach branch [dict get $schema allOf] {
            foreach k [::aurig::core::schema::_known_props $branch $defs] { lappend props $k }
        }
    }
    foreach key {if then else} {
        if {[dict exists $schema $key]} {
            foreach k [::aurig::core::schema::_known_props [dict get $schema $key] $defs] { lappend props $k }
        }
    }
    return [lsort -unique $props]
}

# True if value validates against schema with no errors (warnings ignored).
proc ::aurig::core::schema::_matches {value schema defs} {
    set errs {}
    set warns {}
    ::aurig::core::schema::_validate $value $schema $defs "<cond>" errs warns 0
    return [expr {[llength $errs] == 0}]
}

proc ::aurig::core::schema::_validate {value schema defs path errorsVar warningsVar {warn_unknown 1}} {
    upvar 1 $errorsVar errors $warningsVar warnings
    set schema [::aurig::core::schema::_resolve $schema $defs]

    if {[dict exists $schema const]} {
        if {$value ne [dict get $schema const]} {
            lappend errors "$path: expected const '[dict get $schema const]', got '$value'"
        }
    }
    if {[dict exists $schema enum]} {
        if {[lsearch -exact [dict get $schema enum] $value] < 0} {
            lappend errors "$path: '$value' is not one of [dict get $schema enum]"
        }
    }
    if {[dict exists $schema type]} {
        if {![::aurig::core::schema::_type_ok $value [dict get $schema type]]} {
            lappend errors "$path: expected type [dict get $schema type]"
            return
        }
    }

    if {[dict exists $schema minLength]} {
        if {[string length $value] < [dict get $schema minLength]} {
            lappend errors "$path: string shorter than minLength [dict get $schema minLength]"
        }
    }
    if {[dict exists $schema pattern]} {
        if {![regexp -- [dict get $schema pattern] $value]} {
            lappend errors "$path: '$value' does not match pattern [dict get $schema pattern]"
        }
    }

    # Array checks. `minItems` is a DECIDABLE count and fires UNCONDITIONALLY
    # (regardless of `_is_map`): a map-looking array must not escape it -- e.g.
    # {type array minItems 3} given `alpha beta` (llength 2) is rejected.
    #
    # Per-element `items` validation, by contrast, stays gated on the `_is_map`
    # identifier-key heuristic: it validates a list of multi-key objects
    # (elements carry spaces -> NOT map-looking, e.g. file_sets.rtl entries get
    # their required-key checks) but SKIPS a list that merely LOOKS like a
    # 1-pair dict ([pins.xdc timing.xdc] -> _is_map true). We do not force item
    # validation on a map-looking list -- elements vs k/v pairs are
    # indistinguishable there, and forcing it would reintroduce the type-collapse
    # mis-discrimination and still couldn't reject under lenient scalars. That
    # skip is divergence-envelope item 5; the authoritative item check is build's.
    if {[dict exists $schema minItems] && ![catch {llength $value} _nitems] \
            && $_nitems < [dict get $schema minItems]} {
        lappend errors "$path: fewer than minItems [dict get $schema minItems] items"
    }
    set vmap [::aurig::core::schema::_is_map $value]
    if {!$vmap && [dict exists $schema items]} {
        set i 0
        foreach item $value {
            ::aurig::core::schema::_validate $item [dict get $schema items] $defs \
                "$path\[$i\]" errors warnings $warn_unknown
            incr i
        }
    }

    # Object validation runs whenever the schema expects an object AND the value
    # is dict-usable (`dict size` succeeds: a real mapping, an empty value, or a
    # mapping whose keys are non-identifiers like `$schema`). It is keyed on
    # SCHEMA INTENT + dict-usability, NOT on `_is_map`, so:
    #   - required keys are enforced for `{}` / `device: {}` / `tool.synth: {}`
    #     (dict ops on "" yield no keys -> reported missing); AND
    #   - an object carrying unknown/extra keys (e.g. a top-level `$schema`, or
    #     future keys) is validated as an object and its unknown keys take the
    #     WARNING path below -- a forward-compat WARNING, never a hard reject.
    # A non-empty non-dict scalar where an object is expected was already
    # rejected by the `object` type check above (it returns early).
    if {[::aurig::core::schema::_schema_expects_object $schema] && ![catch {dict size $value}]} {
        if {[dict exists $schema required]} {
            foreach req [dict get $schema required] {
                if {![dict exists $value $req]} {
                    lappend errors "$path: missing required key '$req'"
                }
            }
        }
        set props {}
        if {[dict exists $schema properties]} { set props [dict get $schema properties] }
        dict for {k sub} $props {
            if {[dict exists $value $k]} {
                ::aurig::core::schema::_validate [dict get $value $k] $sub $defs \
                    "$path.$k" errors warnings $warn_unknown
            }
        }
        if {[dict exists $schema additionalProperties] \
                && [::aurig::core::schema::_is_map [dict get $schema additionalProperties]]} {
            set addl [dict get $schema additionalProperties]
            dict for {k v} $value {
                if {![dict exists $props $k]} {
                    ::aurig::core::schema::_validate $v $addl $defs \
                        "$path.$k" errors warnings $warn_unknown
                }
            }
        } elseif {$warn_unknown && [llength $props] > 0} {
            set known [::aurig::core::schema::_known_props $schema $defs]
            dict for {k v} $value {
                if {[lsearch -exact $known $k] < 0} {
                    lappend warnings "\[WARN\] $path.$k: unknown key (ignored; forward-compat)"
                }
            }
        }
    }

    if {[dict exists $schema allOf]} {
        foreach branch [dict get $schema allOf] {
            ::aurig::core::schema::_validate $value $branch $defs $path errors warnings $warn_unknown
        }
    }

    if {[dict exists $schema if]} {
        if {[::aurig::core::schema::_matches $value [dict get $schema if] $defs]} {
            if {[dict exists $schema then]} {
                ::aurig::core::schema::_validate $value [dict get $schema then] $defs $path errors warnings $warn_unknown
            }
        } elseif {[dict exists $schema else]} {
            ::aurig::core::schema::_validate $value [dict get $schema else] $defs $path errors warnings $warn_unknown
        }
    }

    if {[dict exists $schema not]} {
        if {[::aurig::core::schema::_matches $value [dict get $schema not] $defs]} {
            lappend errors "$path: value must not match the 'not' subschema"
        }
    }

    if {[dict exists $schema oneOf]} {
        set n 0
        foreach branch [dict get $schema oneOf] {
            if {[::aurig::core::schema::_matches $value $branch $defs]} { incr n }
        }
        # See header note: "at least one" rather than strict "exactly one".
        if {$n < 1} {
            lappend errors "$path: matches none of oneOf"
        }
    }
}

# Validate a NORMALIZED manifest dict. Returns warning lines; raises a
# ManifestError (one line per violation) if invalid.
proc ::aurig::core::schema::validate {cfg} {
    set schema [::aurig::core::schema::_load_schema]
    set defs {}
    if {[dict exists $schema {$defs}]} { set defs [dict get $schema {$defs}] }
    set errors {}
    set warnings {}
    ::aurig::core::schema::_validate $cfg $schema $defs "<root>" errors warnings 1
    if {[llength $errors]} {
        ::aurig::core::schema::_err [join $errors "\n"]
    }
    return $warnings
}

#=============================================================================
# Checksum drift guard
#=============================================================================
# Verify the vendored manifest-v1.json still matches the pinned SHA-256.
# Raises on drift. Requires tcllib `sha256`.
proc ::aurig::core::schema::verify_schema_checksum {} {
    variable schema_file
    variable schema_sha256
    if {[catch {package require sha256}]} {
        ::aurig::core::schema::_err \
            "checksum drift guard requires tcllib 'sha256' (install tcllib)."
    }
    set f [open $schema_file rb]
    set data [read $f]
    close $f
    set actual [string tolower [::sha2::sha256 -hex $data]]
    if {$actual ne $schema_sha256} {
        ::aurig::core::schema::_err [join [list \
            "vendored manifest-v1.json has DRIFTED from its pinned checksum." \
            "  file    : $schema_file" \
            "  expected: $schema_sha256" \
            "  actual  : $actual" \
            "Re-vendor byte-identically from aurig-build and update\
 ::aurig::core::schema::schema_sha256, OR revert the unintended edit." ] "\n"]
    }
    return 1
}

#=============================================================================
# load_manifest  --  full pipeline, returns {canonicalCfg warningsList}
#=============================================================================
proc ::aurig::core::schema::load_manifest {path} {
    ::aurig::core::schema::require_libs
    set cfg [::aurig::core::schema::read_manifest $path]
    lassign [::aurig::core::schema::normalize $cfg] cfg norm_warns
    set val_warns [::aurig::core::schema::validate $cfg]
    return [list $cfg [concat $norm_warns $val_warns]]
}

#=============================================================================
# scan_project  --  the parser-class CONSUMER
#
# Runs the full load pipeline, then projects the canonical manifest onto the
# read-only view this repo's parser/lint/doc layers consume:
#   schema_version, project_name, project_root (resolved), top, top_file
#   (resolved via name->file resolution), device_vendor (read-only; vendor
#   INFERENCE is PR-B), external_libraries (NEVER the legacy `libraries`),
#   include_dirs_global, generics, file_sets.rtl+sim (globbed file records),
#   and ip_cores passed through OPAQUELY (black box; cracking is PR-B).
#
# This is the ONLY consumer of external_libraries on the schema path, and it
# reads it post-normalize -- so the `libraries`->`external_libraries` rename is
# atomic with the normalize producer: there is no intermediate that reads the
# old key.
#=============================================================================
proc ::aurig::core::schema::scan_project {path} {
    lassign [::aurig::core::schema::load_manifest $path] cfg warns

    set manifest_dir [file dirname [file normalize $path]]

    # project_root: relative to the manifest's own directory (matches the
    # YAML collector's convention); "."/empty -> the manifest dir.
    set proj_root $manifest_dir
    if {[dict exists $cfg project_root]} {
        set pr [string map {\\ /} [dict get $cfg project_root]]
        if {$pr eq "" || $pr eq "."} {
            set proj_root $manifest_dir
        } elseif {[file pathtype $pr] eq "absolute"} {
            set proj_root $pr
        } else {
            set proj_root [file join $manifest_dir $pr]
        }
    }

    set view [dict create]
    foreach k {schema_version project_name top} {
        dict set view $k [expr {[dict exists $cfg $k] ? [dict get $cfg $k] : ""}]
    }
    dict set view project_root $proj_root
    dict set view device_vendor \
        [expr {[dict exists $cfg device vendor] ? [dict get $cfg device vendor] : ""}]
    dict set view external_libraries \
        [expr {[dict exists $cfg external_libraries] ? [dict get $cfg external_libraries] : {}}]
    dict set view generics \
        [expr {[dict exists $cfg generics] ? [dict get $cfg generics] : {}}]
    dict set view include_dirs_global \
        [expr {[dict exists $cfg include_dirs_global] ? [dict get $cfg include_dirs_global] : {}}]
    # ip_cores: pass through OPAQUELY (black box).
    dict set view ip_cores \
        [expr {[dict exists $cfg ip_cores] ? [dict get $cfg ip_cores] : {}}]

    # File inventory from file_sets.rtl + file_sets.sim (globs expanded).
    set rtl_files [::aurig::core::schema::_collect_fileset $cfg $proj_root rtl]
    set sim_files [::aurig::core::schema::_collect_fileset $cfg $proj_root sim]
    dict set view file_sets [dict create rtl $rtl_files sim $sim_files]

    # top name->file resolution (the one place core does MORE than build).
    lassign [::aurig::core::schema::_resolve_top $cfg $proj_root $rtl_files] top_file top_warn
    dict set view top_file $top_file
    if {$top_warn ne ""} { lappend warns $top_warn }

    dict set view warnings $warns
    return $view
}

# Expand one file_sets group into flat file records.
# Record keys: lib, src (resolved path), vhdl_std, srcset.
proc ::aurig::core::schema::_collect_fileset {cfg proj_root group} {
    set out {}
    if {![dict exists $cfg file_sets $group]} { return $out }
    foreach entry [dict get $cfg file_sets $group] {
        if {![::aurig::core::schema::_is_map $entry]} { continue }
        set lib [expr {[dict exists $entry lib] ? [dict get $entry lib] : "work"}]
        set vhdl_std [expr {[dict exists $entry vhdl_std] ? [dict get $entry vhdl_std] : ""}]
        set globs [expr {[dict exists $entry src] ? [dict get $entry src] : {}}]
        foreach g $globs {
            set gabs [string map {\\ /} $g]
            if {[file pathtype $gabs] ne "absolute"} {
                set gabs [file join $proj_root $gabs]
            }
            foreach f [::aurig::core::util::_expand_glob_pattern $gabs] {
                set full [string map {\\ /} $f]
                lappend out [dict create \
                    lib      $lib \
                    src      $full \
                    vhdl_std $vhdl_std \
                    srcset   $group]
            }
        }
    }
    return $out
}

# Does VHDL file $f declare an entity named $name?
#   1  -> yes;  0 -> parsed, but not declared;  -1 -> can't tell (non-VHDL or
#   the parser errored). Verilog/SV are not parsed here, hence -1.
proc ::aurig::core::schema::_file_declares_entity {f name} {
    set ext [string tolower [file extension $f]]
    if {$ext ni {.vhd .vhdl}} { return -1 }
    if {[catch {::aurig::core::analyze::vhdlscan -in $f} pd]} { return -1 }
    if {[lsearch -exact [::aurig::core::analyze::q_entity_names $pd] $name] >= 0} { return 1 }
    return 0
}

# Resolve the top file (F3 hardened). Returns {resolvedPathOrEmpty warningOrEmpty}.
#   - top_file present : anchor to proj_root; it MUST exist (clear error if not)
#     and, for VHDL, MUST declare `top` (clear error if it provably does not;
#     a non-VHDL / unparsable file can't be checked -> accept with a warning).
#   - top_file absent  : scan file_sets.rtl for files declaring `top`.
#       * exactly one  -> that file.
#       * zero         -> empty + warning (top may live in an external lib /
#                         ip_core / non-VHDL source; non-fatal).
#       * more than one -> ERROR listing the candidates and pointing at
#                          top_file as the disambiguator (never silently first).
proc ::aurig::core::schema::_resolve_top {cfg proj_root rtl_files} {
    set top [expr {[dict exists $cfg top] ? [dict get $cfg top] : ""}]

    if {[dict exists $cfg top_file] && [dict get $cfg top_file] ne ""} {
        set raw [dict get $cfg top_file]
        set tf [string map {\\ /} $raw]
        if {[file pathtype $tf] ne "absolute"} { set tf [file join $proj_root $tf] }
        if {![file isfile $tf]} {
            ::aurig::core::schema::_err \
                "top_file does not exist on disk: '$tf' (from top_file='$raw'\
 anchored at project_root='$proj_root'). Fix the path."
        }
        if {$top ne ""} {
            set d [::aurig::core::schema::_file_declares_entity $tf $top]
            if {$d == 0} {
                ::aurig::core::schema::_err \
                    "top_file '$tf' does not declare the top entity '$top'.\
 Align 'top' with the entity in 'top_file', or point 'top_file' at the file\
 that declares '$top'."
            }
            if {$d == -1} {
                return [list $tf \
                    "\[WARN\] top: could not verify that top_file '$tf' declares\
 entity '$top' (not VHDL or unparsable); proceeding on the explicit top_file."]
            }
        }
        return [list $tf ""]
    }

    if {$top eq ""} { return [list "" ""] }

    set candidates {}
    foreach rec $rtl_files {
        set f [dict get $rec src]
        if {[::aurig::core::schema::_file_declares_entity $f $top] == 1} { lappend candidates $f }
    }
    set candidates [lsort -unique $candidates]
    if {[llength $candidates] == 0} {
        return [list "" \
            "\[WARN\] top: could not resolve entity '$top' to a file by scanning\
 file_sets.rtl; set 'top_file' to the explicit path."]
    }
    if {[llength $candidates] > 1} {
        ::aurig::core::schema::_err \
            "top: entity '$top' is declared in multiple RTL files:\
 [join $candidates {, }]. Disambiguate by setting 'top_file' to the intended\
 path."
    }
    return [list [lindex $candidates 0] ""]
}
