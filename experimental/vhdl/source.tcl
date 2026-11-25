namespace eval ::vhdl_index {
    variable sourceSerial 0
    variable readerPath {}
}

proc ::vhdl_index::load_reader {path} {
    variable readerPath
    set path [file normalize $path]
    if {$readerPath ne {} || [info commands ::aurig::core::util::read_vhdl_source] ne {}} {
        error "Load the experimental reader once in a fresh interpreter"
    }
    source $path
    set readerPath $path
}

proc ::vhdl_index::snapshot {sourceId decoded} {
    set text [dict get $decoded text]
    set lines {0}
    for {set newline [string first "\n" $text]} {$newline >= 0} {
        set newline [string first "\n" $text $start]
    } {
        set start [expr {$newline + 1}]
        lappend lines $start
    }
    return [dict merge $decoded [dict create id $sourceId length [string length $text] line_starts $lines]]
}

proc ::vhdl_index::slice {snapshot span} {
    lassign $span start end
    if {$start < 0 || $end < $start || $end > [dict get $snapshot length]} {
        error "Source span out of bounds: $span"
    }
    return [string range [dict get $snapshot text] $start [expr {$end - 1}]]
}

proc ::vhdl_index::position {snapshot offset} {
    if {$offset < 0 || $offset > [dict get $snapshot length]} {
        error "Source position out of bounds: $offset"
    }
    set starts [dict get $snapshot line_starts]
    set lo 0
    set hi [llength $starts]
    while {$hi - $lo > 1} {
        set mid [expr {($hi + $lo) / 2}]
        if {[lindex $starts $mid] <= $offset} {
            set lo $mid
        } else {
            set hi $mid
        }
    }
    return [list [expr {$lo + 1}] [expr {$offset - [lindex $starts $lo]}]]
}

# The caller initializes the cursor to zero and supplies nondecreasing offsets.
proc ::vhdl_index::next_position {snapshot offset lineVar} {
    upvar 1 $lineVar line
    set starts [dict get $snapshot line_starts]
    if {$offset < [lindex $starts $line] || $offset > [dict get $snapshot length]} {
        error "Source position out of bounds for line cursor: $offset"
    }
    set count [llength $starts]
    while {$line + 1 < $count && [lindex $starts [expr {$line + 1}]] <= $offset} {
        incr line
    }
    return [list [expr {$line + 1}] [expr {$offset - [lindex $starts $line]}]]
}
