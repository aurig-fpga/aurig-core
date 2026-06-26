# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# ::aurig::core::analyze – Query helpers for parsed dict
# Notes  : Read-only utilities; they do not mutate the parse dict.
#=============================================================================
namespace eval ::aurig::core::analyze {
    namespace export \
        q_meta \
        q_libraries q_uses \
        q_entities q_entity q_entity_names q_entity_generics q_entity_ports \
        q_architectures q_arch_names q_arch_by_name q_archs_of_entity \
        q_arch_decls q_arch_decls_by_kind q_arch_signals q_arch_processes \
        q_arch_instantiations q_arch_assignments q_arch_generates \
        q_arch_instantiations_info q_arch_functions q_arch_procedures \
        q_packages q_pkg_by_name q_pkg_decls q_pkg_decls_by_kind \
        q_pkgbody_by_name q_pkgbody_functions q_pkgbody_procedures \
        q_find_first q_filter q_filter_re q_list_keys q_has_key \
        q_dump_summary

    #=========================#
    # Low-level safe getters  #
    #=========================#

    # Internal: assert dict and fetch key or empty-list if missing
    proc _safe_get_list {D key} {
        if {[catch {dict size $D}]} { return {} }
        if {![dict exists $D $key]} { return {} }
        set v [dict get $D $key]
        # Some producers pre-create {}; ensure a list is returned
        if {[llength $v] == 0} { return {} }
        return $v
    }

    # Internal: ensure item is a dict (for defensive filtering)
    proc _is_dict {x} {
        expr {![catch {dict size $x}]}
    }

    #=========================#
    # Utilities for filtering #
    #=========================#

    # q_filter — filter list of dicts by exact key=value matches (AND across pairs)
    # Example: q_filter $decls {kind signal mode in}
    proc q_filter {listOfDict kvPairs} {
        set out {}
        foreach d $listOfDict {
            if {![_is_dict $d]} { continue }
            set ok 1
            foreach {k v} $kvPairs {
                if {![dict exists $d $k]} { set ok 0; break }
                if {[dict get $d $k] ne $v} { set ok 0; break }
            }
            if {$ok} { lappend out $d }
        }
        return $out
    }

    # q_filter_re — filter list of dicts by regexp on one key
    # Example: q_filter_re $decls name {^data_}
    proc q_filter_re {listOfDict key re} {
        set out {}
        foreach d $listOfDict {
            if {![_is_dict $d]} { continue }
            if {![dict exists $d $key]} { continue }
            set val [dict get $d $key]
            if {[regexp -- $re $val]} { lappend out $d }
        }
        return $out
    }

    # q_find_first — return first dict matching exact key=value pairs; "" if none
    proc q_find_first {listOfDict kvPairs} {
        foreach d $listOfDict {
            if {![_is_dict $d]} { continue }
            set ok 1
            foreach {k v} $kvPairs {
                if {![dict exists $d $k]} { set ok 0; break }
                if {[dict get $d $k] ne $v} { set ok 0; break }
            }
            if {$ok} { return $d }
        }
        return ""
    }

    #=========================#
    # Meta, libraries, uses   #
    #=========================#

    # q_meta — return meta dict {file parsed_at sha1}
    proc q_meta {D} {
        if {[catch {dict get $D meta} m]} { return {} }
        return $m
    }

    proc q_libraries {D} {
        _safe_get_list $D libraries
    }

    proc q_uses {D} {
        _safe_get_list $D uses
    }

    #=========================#
    # Entities                #
    #=========================#

    # q_entities — list of entity dicts
    proc q_entities {D} {
        _safe_get_list $D entities
    }

    # q_entity_names — list of entity names
    proc q_entity_names {D} {
        set out {}
        foreach e [q_entities $D] {
            if {[_is_dict $e] && [dict exists $e name]} {
                lappend out [dict get $e name]
            }
        }
        return $out
    }

    # q_entity — get entity dict by name ("" if not found)
    proc q_entity {D name} {
        q_find_first [q_entities $D] [list name $name]
    }

    # q_entity_generics — list of generics for entity name
    proc q_entity_generics {D name} {
        set e [q_entity $D $name]
        if {$e eq ""} { return {} }
        if {![dict exists $e generics]} { return {} }
        return [dict get $e generics]
    }

    # q_entity_ports — list of ports for entity name; optional mode filter
    # mode can be "", "in", "out", "inout", "buffer"
    proc q_entity_ports {D name {mode ""}} {
        set e [q_entity $D $name]
        if {$e eq ""} { return {} }
        if {![dict exists $e ports]} { return {} }
        set L [dict get $e ports]
        if {$mode eq ""} { return $L }
        return [q_filter $L [list mode $mode]]
    }

    #=========================#
    # Architectures           #
    #=========================#

    # q_architectures — list of architecture dicts
    proc q_architectures {D} {
        _safe_get_list $D architectures
    }

    # q_arch_names — list of architecture names
    proc q_arch_names {D} {
        set out {}
        foreach a [q_architectures $D] {
            if {[_is_dict $a] && [dict exists $a name]} {
                lappend out [dict get $a name]
            }
        }
        return $out
    }

    # q_arch_by_name — get architecture dict by name ("" if not found)
    proc q_arch_by_name {D archName} {
        q_find_first [q_architectures $D] [list name $archName]
    }

    # q_archs_of_entity — list of architectures whose 'entity' equals entityName
    proc q_archs_of_entity {D entityName} {
        q_filter [q_architectures $D] [list entity $entityName]
    }

    # q_arch_decls — declarations list of an architecture (by name or dict)
    proc q_arch_decls {D archOrName} {
        set a $archOrName
        if {![_is_dict $a]} {
            set a [q_arch_by_name $D $archOrName]
        }
        if {$a eq ""} { return {} }
        if {![dict exists $a declarations]} { return {} }
        return [dict get $a declarations]
    }

    # q_arch_decls_by_kind — filter declarations by kind (e.g., signal, constant, component, function, procedure)
    proc q_arch_decls_by_kind {D archOrName kind} {
        q_filter [q_arch_decls $D $archOrName] [list kind $kind]
    }

    # Convenience: all signals in an architecture
    proc q_arch_signals {D archOrName} {
        q_arch_decls_by_kind $D $archOrName signal
    }

    # Processes / Instantiations / Assignments / Generates
    proc q_arch_processes {D archOrName} {
        set a $archOrName
        if {![_is_dict $a]} { set a [q_arch_by_name $D $archOrName] }
        if {$a eq ""} { return {} }
        if {![dict exists $a processes]} { return {} }
        return [dict get $a processes]
    }

    proc q_arch_instantiations {D archOrName} {
        set a $archOrName
        if {![_is_dict $a]} { set a [q_arch_by_name $D $archOrName] }
        if {$a eq ""} { return {} }
        if {![dict exists $a instantiations]} { return {} }
        return [dict get $a instantiations]
    }

    # get istantiations dict from architecture. the returna list containing, for each instantiation, a dict with keys:
    #   name: name of the instantiation
    #   line:line numbers where the instantiation occurs
    #   entity: entity being instantiated
    #   library: library of the entity being instantiated (in case of direct instantiation)
    proc q_arch_instantiations_info {D archOrName} {
        set a $archOrName
        if {![_is_dict $a]} { set a [q_arch_by_name $D $archOrName] }
        if {$a eq ""} { return {} }
        set instDict [q_arch_instantiations $D $archOrName]
        # loop on all instantiations
        set instInfoList {}
        foreach inst $instDict {
            set instInfo {}
            if  {[dict exists $inst label]} {
                dict set instInfo label [dict get $inst label]
            }
            if {[dict exists $inst name]} {
                dict set instInfo name [dict get $inst name]
            }
            if {[dict exists $inst line]} {
                dict set instInfo line [dict get $inst line]
            }
            if {[dict exists $inst entity]} {
                dict set instInfo entity [dict get $inst entity]
            }
            if {[dict exists $inst library]} {
                dict set instInfo library [dict get $inst library]
            }
            lappend instInfoList $instInfo
        }
        return $instInfoList
    }

    proc q_arch_assignments {D archOrName} {
        set a $archOrName
        if {![_is_dict $a]} { set a [q_arch_by_name $D $archOrName] }
        if {$a eq ""} { return {} }
        if {![dict exists $a assignments]} { return {} }
        return [dict get $a assignments]
    }

    proc q_arch_generates {D archOrName} {
        set a $archOrName
        if {![_is_dict $a]} { set a [q_arch_by_name $D $archOrName] }
        if {$a eq ""} { return {} }
        if {![dict exists $a generates]} { return {} }
        return [dict get $a generates]
    }

    # return all functions declared in architecture declarations
    proc q_arch_functions {D archOrName} {
        set decls [q_arch_decls_by_kind $D $archOrName function]
        return $decls
    }

    # return all procedures declared in architecture declarations
    proc q_arch_procedures {D archOrName} {
        set decls [q_arch_decls_by_kind $D $archOrName procedure]
        return $decls
    }

    #=========================#
    # Packages and bodies     #
    #=========================#

    proc q_packages {D} {
        _safe_get_list $D packages
    }

    proc q_pkg_by_name {D pkgName} {
        q_find_first [q_packages $D] [list name $pkgName]
    }

    proc q_pkg_decls {D pkgOrName} {
        set p $pkgOrName
        if {![_is_dict $p]} { set p [q_pkg_by_name $D $pkgOrName] }
        if {$p eq ""} { return {} }
        if {![dict exists $p declarations]} { return {} }
        return [dict get $p declarations]
    }

    proc q_pkg_decls_by_kind {D pkgOrName kind} {
        q_filter [q_pkg_decls $D $pkgOrName] [list kind $kind]
    }

    # Package bodies
    proc q_pkgbodies {D} {
        _safe_get_list $D package_bodies
    }

    proc q_pkgbody_by_name {D pkgName} {
        q_find_first [q_pkgbodies $D] [list name $pkgName]
    }

    proc q_pkgbody_functions {D pkgOrName} {
        set pb $pkgOrName
        if {![_is_dict $pb]} { set pb [q_pkgbody_by_name $D $pkgOrName] }
        if {$pb eq ""} { return {} }
        if {![dict exists $pb functions]} { return {} }
        return [dict get $pb functions]
    }

    proc q_pkgbody_procedures {D pkgOrName} {
        set pb $pkgOrName
        if {![_is_dict $pb]} { set pb [q_pkgbody_by_name $D $pkgOrName] }
        if {$pb eq ""} { return {} }
        if {![dict exists $pb procedures]} { return {} }
        return [dict get $pb procedures]
    }

    #=========================#
    # Convenience utilities   #
    #=========================#

    # q_list_keys — return a sorted unique list of values for a given key across a list of dicts
    proc q_list_keys {listOfDict key} {
        set S {}
        foreach d $listOfDict {
            if {![_is_dict $d]} { continue }
            if {![dict exists $d $key]} { continue }
            set v [dict get $d $key]
            if {[lsearch -exact $S $v] < 0} { lappend S $v }
        }
        lsort $S
    }

    # q_has_key — does a dict have key=val (exact)
    proc q_has_key {d key val} {
        expr {[_is_dict $d] && [dict exists $d $key] && ([dict get $d $key] eq $val)}
    }

    #=========================#
    # One-shot summary        #
    #=========================#

    # q_dump_summary — human-readable one-liner per main section (for logs/CLI)
    proc q_dump_summary {D} {
        set meta [q_meta $D]
        set file [expr {$meta ne {} && [dict exists $meta file] ? [dict get $meta file] : "?"}]
        set ents [llength [q_entities $D]]
        set arch [llength [q_architectures $D]]
        set pkgs [llength [q_packages $D]]
        set pbs  [llength [q_pkgbodies $D]]
        set libs [llength [q_libraries $D]]
        set uses [llength [q_uses $D]]
        return [format "file=%s | libraries=%d uses=%d | entities=%d arch=%d | packages=%d pkg_bodies=%d" \
            $file $libs $uses $ents $arch $pkgs $pbs]
    }
}
