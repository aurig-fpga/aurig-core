# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# ::aurig::core::analyze  –  Safe builders for the parse_dict structure
#=============================================================================
namespace eval ::aurig::core::analyze {
    namespace export init add_library add_use \
                     begin_entity add_generic add_port end_entity \
                     add_architecture begin_architecture end_architecture \
                     add_decl add_process add_instantiation add_assignment add_generate \
                     add_package add_package_body \
                     get parse_pretty \
                    add_decl_pkg add_subprog_params_last add_subprog_set_body_last \
                    add_function_body_pkg add_procedure_body_pkg
}

#--- Internal helpers ---------------------------------------------------------
proc ::aurig::core::analyze::_ensure_list {dictVar key} {
    upvar 1 $dictVar D
    if {![dict exists $D $key]} { dict set D $key [list] }
}
proc ::aurig::core::analyze::_append {dictVar key itemDict} {
    upvar 1 $dictVar D
    ::aurig::core::analyze::_ensure_list D $key
    set L [dict get $D $key]
    lappend L $itemDict
    dict set D $key $L
}
proc ::aurig::core::analyze::_push_into_last {dictVar key subkey itemDict} {
    # Append an item into the last element of list $key, under its $subkey list.
    upvar 1 $dictVar D
    set L [dict get $D $key]
    if {[llength $L] == 0} { error "no parent item in '$key' to push into" }
    set last [lindex $L end]
    if {![dict exists $last $subkey]} { dict set last $subkey [list] }
    set subL [dict get $last $subkey]
    lappend subL $itemDict
    dict set last $subkey $subL
    # put back
    set L [lreplace $L end end $last]
    dict set D $key $L
}
proc ::aurig::core::analyze::_set_field_in_last {dictVar key field value} {
    upvar 1 $dictVar D
    set L [dict get $D $key]
    if {[llength $L] == 0} { error "no last item in '$key' to set field '$field'" }
    set last [lindex $L end]
    dict set last $field $value
    set L [lreplace $L end end $last]
    dict set D $key $L
}

# Return current time in ISO-8601.
# Use Zulu (UTC) to avoid platform differences with %z on Windows.
proc ::aurig::core::analyze::_iso8601_now {} {
    # Tcl 8.6: clock format supports -gmt and -format, not -iso
    return [clock format [clock seconds] -gmt 1 -format "%Y-%m-%dT%H:%M:%SZ"]
}

#--- Public API ---------------------------------------------------------------

# Initialize a new parse_dict
proc ::aurig::core::analyze::init {filePath} {
    # Normalize the path (portable absolute path)
    set abs [file normalize $filePath]

    # If you later compute SHA1, set it here; for now leave empty.
    set D [dict create]
    dict set D meta [dict create \
        file       $abs \
        parsed_at  [::aurig::core::analyze::_iso8601_now] \
        sha1       "" \
    ]

    # Pre-create top-level repeatable lists you know you’ll use
    # (not mandatory, but avoids “no such key” checks later).
    foreach key {libraries uses entities architectures packages package_bodies} {
        dict set D $key {}
    }
    return $D
}

# Get helper
proc ::aurig::core::analyze::get {dictVar pathArgs} {
    upvar 1 $dictVar D
    return [dict get $D {*}$pathArgs]
}

# Pretty dump as string (for logs)
proc ::aurig::core::analyze::parse_pretty {dictVar} {
    upvar 1 $dictVar D
    return [dict format $D -indent 2]
}

#----- Libraries & Uses -------------------------------------------------------

proc ::aurig::core::analyze::add_library {dictVar name line {decl ""}} {
    upvar 1 $dictVar D
    set item [dict create name $name line $line]
    if {$decl ne ""} { dict set item decl $decl }
    _append D libraries $item
}

# 'use' clause – pkg can be "" if 'use lib.all;'
proc ::aurig::core::analyze::add_use {dictVar lib pkg selector line {decl ""}} {
    upvar 1 $dictVar D
    set item [dict create lib $lib selector $selector line $line]
    if {$pkg ne ""}  { dict set item pkg $pkg }
    if {$decl ne ""} { dict set item decl $decl }
    _append D uses $item
}

#----- Entities ---------------------------------------------------------------

proc ::aurig::core::analyze::begin_entity {dictVar name file line {comment ""}} {
    upvar 1 $dictVar D
    set item [dict create name $name file $file line $line]
    if {$comment ne ""} { dict set item comment $comment }
    dict set item generics [list]
    dict set item ports    [list]
    _append D entities $item
}

proc ::aurig::core::analyze::add_generic {dictVar name type line {init ""} {comment ""}} {
    upvar 1 $dictVar D
    set g [dict create name $name type $type line $line]
    if {$init ne ""} { dict set g init $init }
    if {$comment ne ""} { dict set g comment $comment }
    _push_into_last D entities generics $g
}

proc ::aurig::core::analyze::add_port {dictVar name mode type line {init ""} {comment ""}} {
    upvar 1 $dictVar D
    set p [dict create name $name mode $mode type $type line $line]
    if {$init ne ""} { dict set p init $init }
    if {$comment ne ""} { dict set p comment $comment }
    _push_into_last D entities ports $p
}

proc ::aurig::core::analyze::end_entity {dictVar} {
    # placeholder if you want to finalize/validate
    return
}

#----- Architectures ----------------------------------------------------------

proc ::aurig::core::analyze::add_architecture {dictVar name entity file line decl_section body_section} {
    upvar 1 $dictVar D
    set item [dict create name $name entity $entity file $file line $line \
                decl_section $decl_section body_section $body_section]
    dict set item declarations [list]
    dict set item processes    [list]
    dict set item instantiations [list]
    dict set item assignments  [list]
    dict set item generates    [list]
    _append D architectures $item
}

# Generic declarative item inside last architecture
# kind: signal|constant|type|subtype|component|alias|...
# For component you can attach generics/ports later with add_decl_component_fields
proc ::aurig::core::analyze::add_decl {dictVar kind name line args} {
    upvar 1 $dictVar D
    set item [dict create kind $kind name $name line $line args {}]
    # args is a flat key/value list, e.g. {type std_logic init '0' comment "description"}
    # Build args as a list containing a dict (to match generic/port structure)
    set comment ""
    set body_declarations {}
    set args_dict [dict create]
    foreach {k v} $args {
        if {$k eq "comment"} {
            set comment $v
        } elseif {$k eq "body_declarations"} {
            set body_declarations $v
        } else {
            dict set args_dict $k $v
        }
    }
    # Store args as a list with the dict as first element
    dict set item args [list $args_dict {}]
    if {$comment ne ""} { dict set item comment $comment }
    if {[llength $body_declarations]} {
        dict set item body_declarations $body_declarations
    }
    _push_into_last D architectures declarations $item
}

# Add/append component fields to the last declaration if needed
proc ::aurig::core::analyze::add_decl_component_fields {dictVar which fields} {
    # which is "generics" or "ports"; fields is a list of item dicts
    upvar 1 $dictVar D
    set archL [dict get $D architectures]
    if {[llength $archL] == 0} { error "no architecture to patch declaration into" }
    set arch [lindex $archL end]
    set declL [dict get $arch declarations]
    if {[llength $declL] == 0} { error "no declaration to patch" }
    set last [lindex $declL end]
    if {![dict exists $last $which]} { dict set last $which [list] }
    set cur [dict get $last $which]
    foreach item $fields { lappend cur $item }
    dict set last $which $cur
    set declL [lreplace $declL end end $last]
    dict set arch declarations $declL
    set archL [lreplace $archL end end $arch]
    dict set D architectures $archL
}

proc ::aurig::core::analyze::add_process {dictVar label sensitivity body line {declarations {}} {comment ""}} {
    upvar 1 $dictVar D
    set item [dict create label $label sensitivity $sensitivity body $body line $line]
    if {[llength $declarations]} { dict set item declarations $declarations }
    if {$comment ne ""} { dict set item comment $comment }
    _push_into_last D architectures processes $item
}

proc ::aurig::core::analyze::add_instantiation {dictVar label entity line {generics_map {}} {ports_map {}} {comment ""}} {
    upvar 1 $dictVar D
    set item [dict create label $label entity $entity line $line]
    dict set item generics_map $generics_map
    dict set item ports_map    $ports_map
    if {$comment ne ""} { dict set item comment $comment }
    _push_into_last D architectures instantiations $item
}

proc ::aurig::core::analyze::add_assignment {dictVar lhs rhs line} {
    upvar 1 $dictVar D
    set item [dict create lhs $lhs rhs $rhs line $line]
    _push_into_last D architectures assignments $item
}

proc ::aurig::core::analyze::add_generate {dictVar label scheme condition body line args} {
    upvar 1 $dictVar D
    set item [dict create label $label scheme $scheme condition $condition body $body line $line]
    # Optional fields for for-generate: loop_var and loop_range
    # Pass as: add_generate D $label "for" $cond $body $line loop_var $var loop_range $range
    foreach {k v} $args {
        dict set item $k $v
    }
    _push_into_last D architectures generates $item
}

#----- Packages ---------------------------------------------------------------

proc ::aurig::core::analyze::add_package {dictVar name file line declarative} {
    upvar 1 $dictVar D
    set item [dict create name $name file $file line $line declarative $declarative]
    dict set item declarations [list]
    dict set item components   [list]
    dict set item generics     [list]
    dict set item ports        [list]
    _append D packages $item
}

proc ::aurig::core::analyze::add_package_body {dictVar name file line body} {
    upvar 1 $dictVar D
    set item [dict create name $name file $file line $line body $body]
    dict set item procedures [list]
    dict set item functions  [list]
    _append D package_bodies $item
}

#------------------------------------------------------------------------------
# add_decl_pkg — like add_decl, but targets the *last package* declarations.
# kind: signal|constant|type|subtype|component|alias|function|procedure|...
# name: identifier
# line: integer or string
# args: flat key/value list, e.g.
#       - for function:  {purity pure return integer params $paramList}
#       - for procedure: {params $paramList}
# Where params is a *list of parameter dicts*:
#       {{name a mode in type integer} {name b mode inout type unsigned(7 downto 0) default (others=>'0')}}
#------------------------------------------------------------------------------
proc ::aurig::core::analyze::add_decl_pkg {dictVar kind name line args} {
    upvar 1 $dictVar D
    # Build the item dict from args
    set item [dict create kind $kind name $name line $line]
    foreach {k v} $args { dict set item $k $v }

    # Fetch last package
    set pkgL [dict get $D packages]
    if {[llength $pkgL] == 0} { error "add_decl_pkg: no package opened; call add_package first" }
    set pkg [lindex $pkgL end]

    # Ensure 'declarations' list exists (it does in add_package, but keep safe)
    if {![dict exists $pkg declarations]} { dict set pkg declarations [list] }
    set declL [dict get $pkg declarations]
    lappend declL $item
    dict set pkg declarations $declL

    # Write back
    set pkgL [lreplace $pkgL end end $pkg]
    dict set D packages $pkgL
}

#------------------------------------------------------------------------------
# add_subprog_params_last — append parameter dict(s) to the *last declaration* in scope.
# scope: "architecture" or "package"
# params: list of dicts {name <id> mode <in|out|inout|buffer> type <vhdl-type> ?default <expr>?}
#------------------------------------------------------------------------------
proc ::aurig::core::analyze::add_subprog_params_last {dictVar scope params} {
    upvar 1 $dictVar D
    switch -- $scope {
        architecture {
            set archL [dict get $D architectures]
            if {[llength $archL] == 0} { error "no architecture to patch" }
            set arch [lindex $archL end]
            set declL [dict get $arch declarations]
            if {[llength $declL] == 0} { error "no declaration to patch" }
            set last [lindex $declL end]
            if {![dict exists $last params]} { dict set last params [list] }
            set cur [dict get $last params]
            foreach p $params { lappend cur $p }
            dict set last params $cur
            set declL [lreplace $declL end end $last]
            dict set arch declarations $declL
            set archL [lreplace $archL end end $arch]
            dict set D architectures $archL
        }
        package {
            set pkgL [dict get $D packages]
            if {[llength $pkgL] == 0} { error "no package to patch" }
            set pkg [lindex $pkgL end]
            set declL [dict get $pkg declarations]
            if {[llength $declL] == 0} { error "no declaration to patch" }
            set last [lindex $declL end]
            if {![dict exists $last params]} { dict set last params [list] }
            set cur [dict get $last params]
            foreach p $params { lappend cur $p }
            dict set last params $cur
            set declL [lreplace $declL end end $last]
            dict set pkg declarations $declL
            set pkgL [lreplace $pkgL end end $pkg]
            dict set D packages $pkgL
        }
        default { error "add_subprog_params_last: scope must be 'architecture' or 'package'" }
    }
}

#------------------------------------------------------------------------------
# add_subprog_set_body_last — set/replace 'body' text on the *last declaration* (arch or pkg).
# Useful if you keep function/procedure body text directly on the decl in architectures.
#------------------------------------------------------------------------------
proc ::aurig::core::analyze::add_subprog_set_body_last {dictVar scope bodyText} {
    upvar 1 $dictVar D
    switch -- $scope {
        architecture {
            set archL [dict get $D architectures]
            if {[llength $archL] == 0} { error "no architecture to patch" }
            set arch [lindex $archL end]
            set declL [dict get $arch declarations]
            if {[llength $declL] == 0} { error "no declaration to patch" }
            set last [lindex $declL end]
            dict set last body $bodyText
            set declL [lreplace $declL end end $last]
            dict set arch declarations $declL
            set archL [lreplace $archL end end $arch]
            dict set D architectures $archL
        }
        package {
            set pkgL [dict get $D packages]
            if {[llength $pkgL] == 0} { error "no package to patch" }
            set pkg [lindex $pkgL end]
            set declL [dict get $pkg declarations]
            if {[llength $declL] == 0} { error "no declaration to patch" }
            set last [lindex $declL end]
            dict set last body $bodyText
            set declL [lreplace $declL end end $last]
            dict set pkg declarations $declL
            set pkgL [lreplace $pkgL end end $pkg]
            dict set D packages $pkgL
        }
        default { error "add_subprog_set_body_last: scope must be 'architecture' or 'package'" }
    }
}

#------------------------------------------------------------------------------
# add_function_body_pkg — append a function *body* inside the last package_body.
# Optional fields (return, params, purity, comment) can be added for
# self-contained bodies. LINT-RULES-DEBT-039 added the optional
# `body_declarations` field carrying the structured variable / constant
# declarations from the function body's declarative region (extracted by
# `_scan_functions`), so the lint symbol-builder can surface those names
# the same way it does for architecture-level subprograms.
#------------------------------------------------------------------------------
proc ::aurig::core::analyze::add_function_body_pkg \
    {dictVar name line body {return_type ""} {params {}} {purity ""} {comment ""} {body_declarations {}}} {

    upvar 1 $dictVar D
    set pbL [dict get $D package_bodies]
    if {[llength $pbL] == 0} { error "add_function_body_pkg: no package_body opened; call add_package_body first" }
    set pb [lindex $pbL end]

    set item [dict create kind function name $name line $line body $body]
    if {$return_type ne ""}        { dict set item return $return_type }
    if {[llength $params]}         { dict set item params $params }
    if {$purity ne ""}             { dict set item purity $purity }
    if {$comment ne ""}            { dict set item comment $comment }
    if {[llength $body_declarations]} { dict set item body_declarations $body_declarations }

    if {![dict exists $pb functions]} { dict set pb functions [list] }
    set L [dict get $pb functions]
    lappend L $item
    dict set pb functions $L

    set pbL [lreplace $pbL end end $pb]
    dict set D package_bodies $pbL
}

#------------------------------------------------------------------------------
# add_procedure_body_pkg — append a procedure *body* inside the last
# package_body. LINT-RULES-DEBT-039 added the optional `body_declarations`
# field (same shape as on add_function_body_pkg).
#------------------------------------------------------------------------------
proc ::aurig::core::analyze::add_procedure_body_pkg \
    {dictVar name line body {params {}} {comment ""} {body_declarations {}}} {

    upvar 1 $dictVar D
    set pbL [dict get $D package_bodies]
    if {[llength $pbL] == 0} { error "add_procedure_body_pkg: no package_body opened; call add_package_body first" }
    set pb [lindex $pbL end]

    set item [dict create kind procedure name $name line $line body $body]
    if {[llength $params]}            { dict set item params $params }
    if {$comment ne ""}               { dict set item comment $comment }
    if {[llength $body_declarations]} { dict set item body_declarations $body_declarations }

    if {![dict exists $pb procedures]} { dict set pb procedures [list] }
    set L [dict get $pb procedures]
    lappend L $item
    dict set pb procedures $L

    set pbL [lreplace $pbL end end $pb]
    dict set D package_bodies $pbL
}
