namespace eval ::vhdl_index {
    variable engine tcl-span-index/1
    # Keep recursive frames inside the default Tcl interpreter nesting budget.
    variable defaultLimits {tokens 2000000 scopes 64 delimiters 256}
}

foreach vhdlIndexModule {source lexer cursor grammar interface object parser coverage} {
    source [file join [file dirname [info script]] $vhdlIndexModule.tcl]
}
unset vhdlIndexModule

proc ::vhdl_index::limits {requested} {
    variable defaultLimits
    set actual $defaultLimits
    dict for {key value} $requested {
        if {![dict exists $defaultLimits $key] || ![string is integer -strict $value] ||
            $value < 1 || $value > [dict get $defaultLimits $key]} {
            return -code error -errorcode {VHDL_INDEX LIMIT} "Invalid limit $key=$value"
        }
        dict set actual $key $value
    }
    return $actual
}

proc ::vhdl_index::analyze_file {path edition {requestedLimits {}}} {
    variable sourceSerial
    variable readerPath
    variable engine
    if {$edition ni {1993 2002 2008}} {
        return -code error -errorcode [list VHDL_INDEX EDITION $edition] \
            "Choose edition 1993, 2002 or 2008. Edition 2019 is unverified."
    }
    set actualLimits [limits $requestedLimits]
    if {$readerPath eq {}} {
        return -code error -errorcode {VHDL_INDEX READER} "Load the pinned Core reader first"
    }

    set time0 [clock microseconds]
    # Let the reader's SOURCE error and options unwind unchanged.
    set decoded [::aurig::core::util::read_vhdl_source $path]
    set time1 [clock microseconds]
    set sourceId [list [file normalize $path] [incr sourceSerial]]
    set source [snapshot $sourceId $decoded]
    set time2 [clock microseconds]
    set tape [lexer::lex $source $edition $actualLimits]
    set time3 [clock microseconds]
    set structure [parser::structure $source $tape $edition $actualLimits]
    set time4 [clock microseconds]
    set coverage [coverage $source $tape $structure]
    set time5 [clock microseconds]

    set timing {}
    foreach stage {reader source_map lexical structural coverage} \
        first [list $time0 $time1 $time2 $time3 $time4] \
        last [list $time1 $time2 $time3 $time4 $time5] {
        dict set timing $stage [expr {$last - $first}]
    }
    set interfaceTime [dict get $structure interface_time_us]
    dict set timing interfaces $interfaceTime
    dict incr timing structural -$interfaceTime
    dict unset structure interface_time_us
    dict unset structure interface_status
    set objectTime [dict get $structure object_time_us]
    dict set timing object_declarations $objectTime
    dict incr timing structural -$objectTime
    dict unset structure object_time_us
    dict unset structure object_status
    return [dict merge $structure $coverage [dict create engine $engine edition $edition \
        source_id $sourceId snapshot $source tape $tape lexical_diagnostics [dict get $tape diagnostics] \
        limits $actualLimits timing_us $timing]]
}
