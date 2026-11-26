# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
set scratch $::env(AURIG_EXPERIMENTAL_SCRATCH)
file mkdir $scratch
proc check {label actual expected} {
    if {$actual ne $expected} {error [list $label expected $expected observed $actual]}
}
proc analyze {text} {
    set path [file join $::scratch family.vhd.fixture]
    set out [open $path w]
    puts $out $text
    close $out
    return [::vhdl_index::analyze_file $path 2008]
}
proc check_mask {r ordinary template} {
    check groups [dict get $r capabilities group_declarations] $ordinary
    check templates [dict get $r capabilities group_templates] $template
    check unrelated [dict get $r capabilities alias_declarations] parsed
}
foreach {text ordinary template kind candidates} {
    {group is (signal);} parsed malformed group_template group_templates
    {group "wrong" is (signal);} parsed malformed group_template group_templates
    {group : t (x);} malformed parsed group group_declarations
    {group missing;} malformed malformed group {group_templates group_declarations}
    {group t is (signal);} parsed parsed group_template {}
    {group g : t (x);} parsed parsed group {}
} {
    set r [analyze "package p is $text end;"]
    check_mask $r $ordinary $template
    set row [lindex [dict get [lindex [dict get $r object_declarations] 0] declarations] 0]
    check kind [dict get $row kind] $kind
    if {$candidates ne {}} {
        check candidates [dict get $row candidate_capabilities] $candidates
        check diagnostic [llength [dict get $row diagnostics]] 1
    }
}
foreach {text form} {{attribute of p : package is 1;} attribute_specification {attribute : integer;} attribute_declaration} {
    set r [analyze "package p is $text end;"]
    set row [lindex [dict get [lindex [dict get $r object_declarations] 0] declarations] 0]
    check attribute_kind [dict get $row kind] $form
    check attribute_coverage [dict get $r capabilities attribute_declarations] malformed
}
set r [analyze {package body p is
 procedure f is group is (signal); begin null; end procedure bad;
end package body wrong;}]
set scope [lindex [dict get $r withdrawn_scopes] 0]
set matched 0
foreach proof [dict get $scope contributors] {
    if {[dict get $proof kind] eq "declaration_candidates"} {
        incr matched
        check retained_candidates [dict get $proof capabilities] group_templates
        check retained_diagnostic [dict get [lindex [dict get $proof diagnostics] 0] code] GROUP_EXPECTED_NAME
    }
}
check candidate_count $matched 1
puts "Candidate families passed on Tcl [info patchlevel]"
