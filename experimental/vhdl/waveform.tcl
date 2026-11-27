# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Connectors and commas only count outside balanced expression groups.
proc ::vhdl_index::grammar::waveform_element {state stops} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set form value
    if {[kind c] eq "null"} {
        set form null
        set value [take c]
    } else {
        set value [concurrent_payload c [concat $stops {after}] MISSING_WAVEFORM]
    }
    set after {}
    set delay {}
    if {[kind c] eq "after"} {
        set after [take c]
        set delay [concurrent_payload c [concat $stops {after}] MISSING_AFTER_TIME]
        if {[kind c] eq "after"} {reject c DUPLICATE_AFTER}
    }
    return [dict create kind $form span [extent c $start] value_span $value after_span $after delay_span $delay]
}

proc ::vhdl_index::grammar::waveform {state stops} {
    upvar 1 $state c
    set start [lindex [span c] 0]
    set unaffected {}
    set elements {}
    set commas {}
    if {[kind c] eq "unaffected"} {
        set unaffected [take c]
        if {[kind c] in {, after}} {reject c INVALID_UNAFFECTED_WAVEFORM}
    } else {
        set elementStops [concat $stops {, unaffected}]
        while {1} {
            lappend elements [waveform_element c $elementStops]
            if {[kind c] ne ","} {break}
            lappend commas [take c]
        }
    }
    return [dict create span [extent c $start] unaffected_span $unaffected \
        elements $elements element_separator_spans $commas]
}

proc ::vhdl_index::grammar::delay_mechanism {state} {
    upvar 1 $state c
    set mode [kind c]
    if {$mode ni {reject inertial transport}} {return {}}
    set start [lindex [span c] 0]
    set rejectKeyword {}
    set time {}
    if {$mode eq "reject"} {
        set rejectKeyword [take c]
        set time [concurrent_payload c {inertial transport when else ,} MISSING_REJECT_TIME]
        set mode inertial
    }
    set keyword [require c $mode EXPECTED_DELAY_MECHANISM]
    return [dict create kind $mode span [extent c $start] keyword_span $keyword \
        reject_span $rejectKeyword reject_time_span $time]
}

# The selected comma belongs to the alternative after WHEN, while the
# waveform comma belongs to an element before WHEN.
proc ::vhdl_index::grammar::selected_choices {state} {
    upvar 1 $state c
    set choices {}
    set bars {}
    set others 0
    while {1} {
        if {[kind c] eq "others"} {
            if {$choices ne {}} {reject c OTHERS_MUST_BE_SOLE_CHOICE}
            lappend choices [dict create kind others span [take c]]
            set others 1
            if {[kind c] eq "|"} {reject c OTHERS_MUST_BE_SOLE_CHOICE}
        } else {
            set choice [concurrent_payload c {| , when else others} MISSING_CHOICE]
            lappend choices [dict create kind opaque span $choice]
        }
        if {[kind c] ne "|"} {break}
        lappend bars [take c]
    }
    return [list $choices $bars $others]
}

proc ::vhdl_index::grammar::selected_values {state {valueGrammar waveform_value} {concurrent 1}} {
    upvar 1 $state c
    set rows {}
    while {1} {
        lassign [$valueGrammar c] valueSpan value
        if {$concurrent && [generate_alternative_start c]} {reject c EXPECTED_WHEN}
        set when [require c when EXPECTED_WHEN]
        lassign [selected_choices c] choices bars others
        set comma {}
        if {[kind c] eq ","} {
            if {$others} {reject c OTHERS_MUST_BE_FINAL}
            set comma [take c]
        }
        lappend rows [dict merge $value [dict create span [extent c [lindex $valueSpan 0]] when_span $when choices $choices \
            choice_separator_spans $bars alternative_separator_span $comma]]
        if {$comma eq {}} {return $rows}
    }
}

proc ::vhdl_index::grammar::conditional_values {state {valueGrammar waveform_value} {concurrent 1}} {
    upvar 1 $state c
    set rows {}
    set category simple
    while {1} {
        lassign [$valueGrammar c] valueSpan value
        set when {}
        set condition {}
        set alternative {}
        if {[kind c] eq "when" && (!$concurrent || ![generate_alternative_start c])} {
            set category conditional
            set when [take c]
            set condition [concurrent_payload c {when else ,} MISSING_CONDITION]
            if {[kind c] eq "else" && (!$concurrent || ![generate_alternative_start c])} {set alternative [take c]}
        }
        lappend rows [dict merge $value [dict create span [extent c [lindex $valueSpan 0]] when_span $when condition_span $condition else_span $alternative]]
        if {$alternative eq {}} {return [list $category $rows]}
    }
}

proc ::vhdl_index::grammar::waveform_value {state} {
    upvar 1 $state c
    set wave [waveform c {when else}]
    set extent [dict get $wave span]
    dict set wave waveform_span $extent
    return [list $extent $wave]
}
