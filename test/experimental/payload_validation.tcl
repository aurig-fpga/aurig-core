# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

source [file join [file dirname [info script]] startup.tcl]
if {[info commands ::vhdl_index::payload::inventory] ne {}} {
    error "ordinary frontend eagerly loaded the payload module"
}
source [file join [file dirname [info script]] .. .. experimental vhdl payload.tcl]
namespace path {::vhdl_index::payload}

proc same {actual expected context} {
    if {$actual ne $expected} {error "$context: expected <$expected>, got <$actual>"}
}
proc value_text {result descriptor} {
    set span [dict get $descriptor span]
    if {$span eq {}} {return {}}
    return [::vhdl_index::slice [dict get $result snapshot] $span]
}
proc select_row {view row args} {
    return [select $view [dict get $row owner_id] [dict get $row occurrence_id] [dict get $row role] {*}$args]
}
proc ast {result id} {
    set node [::vhdl_index::bounded::node $result $id]
    set shape [list [dict get $node kind]]
    foreach connector [dict get $node connectors] {lappend shape [lindex $connector 0]}
    foreach child [dict get $node children] {lappend shape [ast $result $child]}
    return $shape
}
proc root_ids {view} {
    set ids {}
    foreach unit [::vhdl_index::query::units $view] {lappend ids [dict get $unit occurrence_id]}
    return $ids
}
proc failure {script expected} {
    set code [catch {uplevel 1 $script} result options]
    same $code 1 {expected Tcl error}
    same [dict get $options -errorcode] [list VHDL_INDEX $expected] {structured error}
}
proc independently_fenced {result row expected selected} {
    set extent [dict get $row span]
    if {$extent eq {}} {return}
    lassign $extent start end
    same [expr {$end - $start}] [string length $expected] {normalized half-open extent}
    set snapshot [dict get $result snapshot]
    set tape [dict get $result tape]
    set starts [dict get $tape starts]
    # Count token starts independently of the binary adapter.
    set first 0
    set last 0
    foreach token [dict get $tape significant] {
        set offset [lindex $starts $token]
        if {$offset < $start} {incr first}
        if {$offset < $end} {incr last}
    }
    same [dict get $selected token_interval] [list $first $last] {significant-token fence}
    set direct [::vhdl_index::bounded::parse $snapshot $tape [dict get $result edition] \
        [dict get $row entry] $first $last]
    same [dict get $selected grammar] $direct {identical direct P-A grammar outcome}
}

set result [::vhdl_index::analyze_file [file join $tests fixtures payload-integration.vhd.fixture] 2008]
set view [::vhdl_index::regions::view $result]
lassign [root_ids $view] entity architecture
set expected {
    generic_default {{} 8 f(i) {2 + 3 * 4}}
    port_default {{} '0'}
    parameter_default {{} pkg.f(i)}
    scalar_range {{0 to 15} {0 to 8}}
    subtype_range {{} {1 to 9} {3 to 8} {9 to 12} {15 to 25}}
    array_dimension_range {{1 to 2} {9 downto 3} {index_t range 2 to 6}}
    array_dimension_box {<>}
    object_initializer {{} '1' {3 + 5}}
    attribute_value {{8 - 1}}
    file_open_kind {{} {} read_mode}
    file_logical_name {{} {"a"} {"b"}}
    disconnect_time {{4 ns}}
    block_guard {{} {G = 14}}
    generate_condition {{G = 3} {J = 3}}
    generate_selector {{G mod 3}}
    for_generate_range {{natural range 0 to 7}}
    assert_condition {{G /= 0} {G > 0} {G > 0} {H < 9} {H > 0} {v > 1}}
    assert_report {{} {} {} {} {"asserted"} {"seq"}}
    assert_severity {{} {} {} {} note warning}
    report_value {{"alone"} {"r" & "s"}}
    report_severity {{} warning}
    wait_condition {{} {v /= 8}}
    wait_timeout {{} {2 ns}}
    return_value {{} {9 ** 2}}
    if_condition {{v < 2} {v = 0}}
    case_selector {{v + 2}}
    while_condition {{v < 7}}
    next_condition {{} {v = 1}}
    exit_condition {{} {v = 5}}
    for_loop_range {{7 downto 4}}
    assignment_selector {{} {} {} {} {} {} G v v}
    assignment_condition {{} {} {G = 2} {G > 2}}
    variable_value {3 5 6 7 9 ii}
    force_value {'0' '1' '1'}
    waveform_value {'0' '0' '1' '1'}
    waveform_delay {{} {} {2 ns} {3 ns} {4 ns}}
    reject_time {{} {} {} {} {1 ns}}
    null_waveform {null}
    unaffected_waveform {unaffected}
}
set observed {}
set checked 0
set known {}
set owners {}
foreach root [list $entity $architecture] {
    set inv [inventory $view $root subtree]
    same [dict get $inv completeness] complete {proved unit subtree}
    set prior -1
    foreach row [dict get $inv rows] {
        set role [dict get $row role]
        set text [value_text $result $row]
        set at [lindex [dict get $row span] 0]
        if {$at eq {}} {set at [lindex [dict get $row occurrence_id] 2]}
        if {$at < $prior} {error "inventory source order regressed"}
        set prior $at
        dict lappend observed $role $text
        set selected [select_row $view $row]
        same [dict get $selected descriptor] $row {registry and selective descriptor}
        switch -- [dict get $row presence] {
            present {
                if {[dict get $selected status] ni {parsed ambiguous}} {error "unproved positive case: $selected"}
                independently_fenced $result $row $text $selected
                incr checked
            }
            absent {same [dict get $selected status] absent {optional slot}}
            atomic {same [dict get $selected status] atomic {owning production marker}}
            default {error "unexpected availability: $row"}
        }
        set key [list [dict get $row occurrence_id] $role]
        same [dict exists $known $key] 0 {one canonical occurrence per syntactic role}
        dict set known $key $row
        dict set owners [dict get $row owner_id] 1
        if {$text eq {2 + 3 * 4}} {set precedence $selected; set firstRow $row}
        if {$text eq {f(i)}} {set ambiguity $selected}
        if {$text eq {7 downto 4}} {set loopRange $row}
    }
}
same [lsort [dict keys $observed]] [lsort [dict keys $expected]] {role coverage}
dict for {role texts} $expected {
    same [lsort [dict get $observed $role]] [lsort $texts] $role
}
set parsed [dict get $precedence grammar]
same [ast $parsed [dict get $parsed root]] {binary + number {binary * number number}} {precedence tree}
set parsed [dict get $ambiguity grammar]
set top [lindex [nodes $ambiguity [list [dict get $parsed root]]] 0]
same [dict get $top candidates] {indexed slice function_call type_conversion} {ambiguous suffix categories}
same [dict get [select $view [dict get $firstRow owner_id] [dict get $firstRow occurrence_id] assignment_target] status] \
    not_applicable {valid occurrence with unrelated role}
same [dict get [inventory $view $entity] completeness] not_applicable {unit does not duplicate dedicated interface owner}

set loopOwner [dict get $loopRange owner_id]
set loopRows [::vhdl_index::query::direct $view $loopOwner loop_parameters]
set loopParameter [lindex [dict get $loopRows rows] 0]
same [dict get $loopParameter occurrence_id] [dict get $loopRange occurrence_id] {existing loop parameter identity}
same [lsearch -exact [dict get [inventory $view $loopOwner] rows] $loopRange] 0 {dedicated loop owner}
set selections [list [list $entity subtree] [list $architecture subtree]]
set batch [validate $view $selections]
set overlapping [validate $view [concat $selections [list [list $loopOwner direct] [list $architecture subtree]]]]
same [dict get $overlapping rows] [dict get $batch rows] {overlapping projections share occurrence identities}
same [dict get $overlapping outcomes] [dict get $batch outcomes] {overlapping projections do not repeat parses}
same [expr {[dict get $overlapping duplicate_visits] > 0}] 1 {overlap exercised}
same [dict get [validate $view [lreverse $selections]] rows] [dict get $batch rows] {selection ordering}
same [dict get $batch status] finished {complete batch request}
same [llength [dict get $batch outcomes]] $checked {all admitted outcomes}
same [dict get $batch retained_nodes] 0 {no retained arenas}
foreach outcome [dict get $batch outcomes] {
    same [dict exists $outcome rows] 0 {compact outcome}
    same [dict exists $outcome root] 0 {transient roots}
}
foreach {budget reason} {{rows 2} rows {parses 1} parses {tokens 1} tokens {selections 1} selections} {
    set exhausted [validate $view $selections $budget]
    same [dict get $exhausted status] incomplete {batch resource exhaustion}
    same [dict get $exhausted limit] $reason {specific budget}
    same [expr {[dict get $exhausted remaining] ne "0"}] 1 {unvalidated roles remain}
}
set limited [select_row $view $firstRow {nodes 1}]
same [dict get $limited status] unavailable {per-interval node limit}
same [dict get $limited grammar root] {} {unavailable grammar withdraws tentative root}
failure {nodes $precedence [lrepeat 257 0]} PAYLOAD_PROJECTION_LIMIT
for {set i 0} {$i < 5} {incr i} {
    same [select_row $view $firstRow] $precedence {repeat without side effects}
}

set other [::vhdl_index::analyze_file [file join $tests fixtures payload-integration.vhd.fixture] 2008]
set foreign [::vhdl_index::regions::view $other]
failure {inventory $foreign $entity subtree} REGION_ID
failure {select $view [dict get $firstRow owner_id] [list [dict get $other source_id] interface_item 0] generic_default} REGION_ID
failure {select $view [dict get $firstRow owner_id] [list [dict get $result source_id] interface_item 9999999] generic_default} PAYLOAD_OCCURRENCE
failure {select $view $architecture [dict get $firstRow occurrence_id] generic_default} PAYLOAD_OCCURRENCE
set spliced $view
dict set spliced result snapshot [dict get $other snapshot]
failure {select_row $spliced $firstRow} PAYLOAD_PROVENANCE
set spliced $view
dict set spliced result tape [dict get $other tape]
failure {select_row $spliced $firstRow} PAYLOAD_PROVENANCE
set spliced $view
dict set spliced result tape [::vhdl_index::lexer::lex [dict get $result snapshot] 1993 [dict get $result limits]]
failure {validate $spliced $selections} PAYLOAD_PROVENANCE
unset other foreign spliced

set bad [::vhdl_index::analyze_file [file join $tests fixtures payload-recovery.vhd.fixture] 2008]
set badView [::vhdl_index::regions::view $bad]
lassign [root_ids $badView] badEntity badArch
set badInv [inventory $badView $badArch subtree]
same [dict get $badInv completeness] partial {withdrawn subtrees and malformed carriers}
same [dict get [inventory $badView $badEntity subtree] completeness] partial {unknown interface item}
set coverageBefore [::vhdl_index::query::subtree $badView $badArch object_declarations]
set classified {}
foreach row [dict get $badInv rows] {
    if {[dict get $row presence] in {absent atomic}} {continue}
    set text [value_text $bad $row]
    set selected [select_row $badView $row]
    dict set classified $text [dict get $selected status]
    if {[dict get $selected status] in {unsupported malformed}} {
        same [dict get $selected unresolved] [list [dict get $row span]] {precise unresolved carrier}
        same [dict get $selected grammar rows] {} {failed grammar publishes no nodes}
    }
}
foreach {text status} {
    {0 to 3 natural} parsed {a + * b} malformed a(i) ambiguous {and a or b} unsupported
    {x(2 downto 0) = y} parsed {f(1, 2) > 0} ambiguous {x'left(1) = 0} ambiguous
    {42 > 1} parsed {17 > 3} parsed {} unavailable
} {
    same [dict get $classified $text] $status {recovery and ambiguity controls}
}
same [dict exists $classified 12] 0 {withdrawn initializer}
same [dict exists $classified 14] 0 {withdrawn sequential assignment}
set lost 0
foreach proof [dict get $badInv evidence] {
    if {[dict get $proof availability] ne "withdrawn"} {continue}
    incr lost
    set direct [inventory $badView [dict get $proof evidence_id]]
    same [dict get $direct completeness] unavailable {direct withdrawn owner}
    same [dict get $direct rows] {} {withdrawn owner has no trusted carriers}
}
same [expr {$lost >= 2}] 1 {compositional owner loss}
same [::vhdl_index::query::subtree $badView $badArch object_declarations] $coverageBefore \
    {bounded failures preserve structural projection}
set badBatch [validate $badView [list [list $badArch subtree]] {diagnostics 1}]
same [dict get $badBatch status] incomplete {diagnostic budget}
same [dict get $badBatch limit] diagnostics {diagnostic budget reason}

# Simulate compatible retained projections to exercise the batch equivalence
# relation even though ordinary grammar rarely gives different slots one fence.
set shared $view
set archRegion [list region [lindex $architecture 2]]
set owner [::vhdl_index::regions::identity $view $archRegion]
set carrierRows [dict get $shared result concurrent_statements [list [lindex $archRegion 1] concurrent_assertions]]
set firstAssertion [lindex $carrierRows 0]
dict set firstAssertion report_span [dict get $firstAssertion condition_span]
lset carrierRows 0 $firstAssertion
dict set shared result concurrent_statements [list [lindex $archRegion 1] concurrent_assertions] $carrierRows
set control [validate $shared [list [list $owner direct]]]
same [dict get $control reused] 1 {same fence and same grammar entry}
set seen {}
foreach descriptor [dict get $control rows] {
    if {[dict get $descriptor span] eq [dict get $firstAssertion condition_span]} {
        dict set seen [dict get $descriptor role] [dict get $descriptor outcome]
    }
}
same [lsort [dict keys $seen]] {assert_condition assert_report} {roles sharing one extent survive separately}
same [dict get $seen assert_condition] [dict get $seen assert_report] {shared batch parse outcome}

if {[info exists ::env(AURIG_EXPERIMENTAL_SCRATCH)]} {
    set scratch $::env(AURIG_EXPERIMENTAL_SCRATCH)
} else {
    set scratch [file join /tmp aurig-payload-[pid]]
}
file mkdir $scratch
set path [file join $scratch mixed.vhd.fixture]
set fd [open $path wb]
puts -nonewline $fd [encoding convertto utf-8 \
    "entity mix is end;\r\narchitecture rtl of mix is\r\nconstant v : integer := -- café\r\n 2 +\r 3 -- après\r\n;\nbegin end;\r\n"]
close $fd
foreach edition {1993 2002 2008} {
    set mixed [::vhdl_index::analyze_file $path $edition]
    set mixedView [::vhdl_index::regions::view $mixed]
    set roots [root_ids $mixedView]
    set mixedRows [dict get [inventory $mixedView [lindex $roots 1] subtree] rows]
    same [llength $mixedRows] 1 {mixed source payload count}
    set row [lindex $mixedRows 0]
    set query [select_row $mixedView $row]
    same [value_text $mixed $row] "2 +\n 3" {normalized extent excludes outside trivia}
    independently_fenced $mixed $row "2 +\n 3" $query
    lassign [dict get $row span] start end
    set normalized [dict get $mixed snapshot text]
    same $start [string first "2 +" $normalized] {Unicode offset before expression}
    set triviaStart [string first {-- café} $normalized]
    set triviaEnd [string first ";" $normalized $end]
    same [::vhdl_index::bounded::interval [dict get $mixed tape] [list $triviaStart $triviaEnd]] \
        [dict get $query token_interval] {leading and trailing trivia adapt to the same fence}
}
unset result view known owners firstRow parsed ambiguity
same [llength [nodes $precedence [list [dict get $precedence grammar root]]]] 1 {selective value outlives its view}
puts "Payload validation passed: $checked independently checked present carriers, [dict size $expected] roles"
