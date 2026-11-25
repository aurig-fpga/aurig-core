# The Python drivers verify the source bytes against Git before either load.
set tests [file dirname [file normalize [info script]]]
set core [file dirname [file dirname $tests]]
set workspace [file dirname [file dirname $core]]
set archivedTask [file join $workspace _tasks AURIG-004-C]
set frontend [file join $core experimental vhdl frontend.tcl]
if {[info exists ::env(AURIG_EXPERIMENTAL_FRONTEND)]} {
    set frontend $::env(AURIG_EXPERIMENTAL_FRONTEND)
}
if {[lsearch -exact $argv --baseline-engine] >= 0} {
    set argv [lsearch -all -inline -not -exact $argv --baseline-engine]
    set frontend [file join $workspace _tasks AURIG-004-B lib frontend.tcl]
}
source $frontend
proc remember_loaded_source {command operation} {
    lappend ::loadedSources [file normalize [lindex $command end]]
}
set loadedSources {}
trace add execution ::source enter remember_loaded_source
if {[lsearch -exact $argv --legacy] >= 0} {
    set argv [lsearch -all -inline -not -exact $argv --legacy]
    package ifneeded aurig::core 0.2.0 [list source [file join $core core.tcl]]
    package require -exact aurig::core 0.2.0
    # The baseline package already sourced the reader; keep that command.
    set ::vhdl_index::readerPath [file join $core util vhdl_source.tcl]
} else {
    ::vhdl_index::load_reader [file join $core util vhdl_source.tcl]
}
trace remove execution ::source enter remember_loaded_source
source [file join $tests projection.tcl]
