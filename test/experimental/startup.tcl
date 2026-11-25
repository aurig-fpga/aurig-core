# The Python drivers verify the source bytes against Git before either load.
set task [file dirname [file dirname [file normalize [info script]]]]
set workspace [file dirname [file dirname $task]]
set core [file join $workspace aurig-core]
set experimentalTask $task
if {[lsearch -exact $argv --baseline-engine] >= 0} {
    set argv [lsearch -all -inline -not -exact $argv --baseline-engine]
    set experimentalTask [file join $workspace _tasks AURIG-004-B]
}
source [file join $experimentalTask lib frontend.tcl]
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
source [file join $task tests projection.tcl]
