# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Script Name  : vhdlscan.tcl
# Namespace    : ::aurig::core::analyze
#-----------------------------------------------------------------------------
# Description: collection of procedures to scan (parse?) a VHDL file with regexps in Tcl
# it is not a full VHDL parser but should be able to parse most of the constructs
# it is intended to be used as a starting point to analyze VHDL files, extract
# main constructs and generate reports
#=============================================================================

namespace eval ::aurig::core::analyze {


	# this file contains procedures for parsing a VHDL file with regexps in Tcl
	# it is not a full VHDl parser but should be able to parse most of the constructs
	# it is intended to be used as a starting point to analyze VHDL files, extract
	# main constructs and generate reports
	# there is a dictionary that is updated with the parsed constructs, you can find the dictionary
	# structure in the Readme.md file
	# read regexps from vhdl_re file

	# Helper proc to extract header metadata from comments
	proc parse_header_metadata {parseDict} {
		upvar 1 $parseDict localDict
		if {![dict exists $localDict comments]} {return}
		if {![dict exists $localDict comments line]} {return}

		set author ""
		set module_name ""
		set library ""
		set project ""
		set company ""
		set description ""
		set notes ""
		set in_header 1
		set in_desc 0
		set in_notes 0

		# Iterate through comments by line number
		set comment_dict [dict get $localDict comments line]
		set sorted_lines [lsort -integer [dict keys $comment_dict]]
		foreach line $sorted_lines {
			if {$line > 50} break ;# Only check first 50 lines for header
			set cmt [dict get $comment_dict $line comment]

			# Check for end of header (long separator or library keyword)
			if {[regexp {^[-=]{10,}} $cmt] && [string length $description] > 0} {
				set in_header 0
				break
			}

			if {$in_header} {
				if {[regexp -nocase {^[\s*]*Module Name\s*:\s*(.+)$} $cmt -> val]} {
					set module_name [string trim $val]
					set in_desc 0
					set in_notes 0
				} elseif {[regexp -nocase {^[\s*]*Library\s*:\s*(.+)$} $cmt -> val]} {
					set library [string trim $val]
					set in_desc 0
					set in_notes 0
				} elseif {[regexp -nocase {^[\s*]*Project\s*:\s*(.+)$} $cmt -> val]} {
					set project [string trim $val]
					set in_desc 0
					set in_notes 0
				} elseif {[regexp -nocase {^[\s*]*Company\s*:\s*(.+)$} $cmt -> val]} {
					set company [string trim $val]
					set in_desc 0
					set in_notes 0
				} elseif {[regexp -nocase {^[\s*]*Author\s*:\s*(.+)$} $cmt -> val]} {
					set author [string trim $val]
					set in_desc 0
					set in_notes 0
				} elseif {[regexp -nocase {^[\s*]*Description\s*:\s*(.*)$} $cmt -> val]} {
					set description [string trim $val]
					set in_desc 1
					set in_notes 0
				} elseif {[regexp -nocase {^[\s*]*Notes?\s*:\s*(.*)$} $cmt -> val]} {
					set notes [string trim $val]
					set in_desc 0
					set in_notes 1
				} elseif {$in_desc && [regexp {^[\s*]*(.+)$} $cmt -> val]} {
					# Continue description on next lines
					set val [string trim $val]
					if {[string length $val] > 0 && ![regexp {^[-=*]+$} $val]} {
						append description " " $val
					}
				} elseif {$in_notes && [regexp {^[\s*]*(.+)$} $cmt -> val]} {
					# Continue notes on next lines
					set val [string trim $val]
					if {[string length $val] > 0 && ![regexp {^[-=*]+$} $val]} {
						append notes " " $val
					}
				}
			}
		}

		# Store metadata in parseDict
		if {$author ne ""} {dict set localDict metadata author $author}
		if {$module_name ne ""} {dict set localDict metadata module_name $module_name}
		if {$library ne ""} {dict set localDict metadata library $library}
		if {$project ne ""} {dict set localDict metadata project $project}
		if {$company ne ""} {dict set localDict metadata company $company}

		# Combine description and notes
		set full_description ""
		if {$description ne ""} {
			set full_description $description
		}
		if {$notes ne ""} {
			if {$full_description ne ""} {
				append full_description ". " $notes
			} else {
				set full_description $notes
			}
		}
		if {$full_description ne ""} {
			dict set localDict metadata description [string trim $full_description]
		}
	}

	proc _lint_enabled {value} {
		switch -- [string tolower [string trim $value]] {
			1 - true - yes - on {return 1}
			default {return 0}
		}
	}

	proc _lint_syntax_error {filename line message} {
		error "ERROR: VHDL lint syntax error in [file tail $filename]:$line: $message"
	}

	proc _mask_vhdl_string_literals {text} {
		set out ""
		set len [string length $text]
		set token_index 0
		for {set i 0} {$i < $len} {incr i} {
			set ch [string index $text $i]
			if {$ch ne "\""} {
				append out $ch
				continue
			}

			set close_index -1
			for {set j [expr {$i + 1}]} {$j < $len} {incr j} {
				if {[string index $text $j] ne "\""} continue
				if {$j + 1 < $len && [string index $text [expr {$j + 1}]] eq "\""} {
					incr j
					continue
				}
				set close_index $j
				break
			}
			if {$close_index < 0} {
				append out [string range $text $i end]
				break
			}

			append out "__Q${token_index}__"
			incr token_index
			set i $close_index
		}
		return $out
	}

	proc _lint_line_has_unterminated_string {line} {
		set in_string 0
		set len [string length $line]
		for {set i 0} {$i < $len} {incr i} {
			set ch [string index $line $i]
			if {!$in_string && $ch eq "-" && $i + 1 < $len && [string index $line [expr {$i + 1}]] eq "-"} {
				return 0
			}
			if {$ch ne "\""} continue
			if {$in_string && $i + 1 < $len && [string index $line [expr {$i + 1}]] eq "\""} {
				incr i
				continue
			}
			set in_string [expr {!$in_string}]
		}
		return $in_string
	}

	proc _lint_code_line {line} {
		set code [::aurig::core::util::strip_vhdl_comment $line]
		set out ""
		set in_string 0
		set len [string length $code]
		for {set i 0} {$i < $len} {incr i} {
			set ch [string index $code $i]
			if {$ch eq "\""} {
				append out " "
				if {$in_string && $i + 1 < $len && [string index $code [expr {$i + 1}]] eq "\""} {
					append out " "
					incr i
					continue
				}
				set in_string [expr {!$in_string}]
			} elseif {$in_string} {
				append out " "
			} elseif {$ch eq "'" && $i + 2 < $len && [string index $code [expr {$i + 2}]] eq "'"} {
				append out "   "
				incr i 2
			} else {
				append out $ch
			}
		}
		return $out
	}

	proc _lint_line_paren_delta {code} {
		set delta 0
		set len [string length $code]
		for {set i 0} {$i < $len} {incr i} {
			set ch [string index $code $i]
			if {$ch eq "("} {
				incr delta
			} elseif {$ch eq ")"} {
				incr delta -1
			}
		}
		return $delta
	}

	proc _validate_vhdl_lint_syntax {content filename} {
		set code_lines {}
		set linenum 0
		foreach line [split $content "\n"] {
			incr linenum
			if {[::aurig::core::analyze::_lint_line_has_unterminated_string $line]} {
				::aurig::core::analyze::_lint_syntax_error $filename $linenum "unterminated string literal"
			}
			lappend code_lines [list $linenum [::aurig::core::analyze::_lint_code_line $line]]
		}

		set in_port_block 0
		set port_depth 0
		set seen_ports {}
		set previous_port_line 0
		set previous_port_closed 1
		set pending_signal_line 0
		for {set i 0} {$i < [llength $code_lines]} {incr i} {
			lassign [lindex $code_lines $i] line code
			set trimmed [string trim $code]
			set lower [string tolower $trimmed]
			if {$trimmed eq ""} continue

			if {$pending_signal_line > 0} {
				if {[string match "*;*" $trimmed]} {
					set pending_signal_line 0
					continue
				}
				if {[regexp -nocase {^\)\s*(is|return|\s|$)} $trimmed]} {
					set pending_signal_line 0
					continue
				}
				if {[regexp -nocase {^(begin|end|signal|constant|variable|type|subtype|function|procedure|component|attribute|alias|architecture|entity|process|port|generic)(\s|;|$)} $trimmed]} {
					::aurig::core::analyze::_lint_syntax_error $filename $pending_signal_line "missing semicolon after signal declaration"
				}
				continue
			}

			if {[regexp -nocase {^entity\s*$} $trimmed]} {
				set next_code ""
				for {set j [expr {$i + 1}]} {$j < [llength $code_lines]} {incr j} {
					lassign [lindex $code_lines $j] next_line next_raw
					set next_code [string trim $next_raw]
					if {$next_code ne ""} break
				}
				if {![regexp -nocase {^[A-Za-z][A-Za-z0-9_]*\s+is(\s|$)} $next_code]} {
					::aurig::core::analyze::_lint_syntax_error $filename $line "missing entity name"
				}
			}
			if {[regexp -nocase {^library\s+\S+} $trimmed] && ![string match "*;" $trimmed]} {
				::aurig::core::analyze::_lint_syntax_error $filename $line "missing semicolon after library declaration"
			}
			if {[regexp -nocase {^use\s+\S+} $trimmed] && ![string match "*;" $trimmed]} {
				::aurig::core::analyze::_lint_syntax_error $filename $line "missing semicolon after use clause"
			}
			if {[regexp -nocase {^signal\s+[A-Za-z][A-Za-z0-9_,\s]*\s*:\s*(.*)$} $trimmed -> signal_tail]} {
				set signal_tail [string trim $signal_tail]
				if {[regexp {^;} $signal_tail]} {
					::aurig::core::analyze::_lint_syntax_error $filename $line "missing signal type"
				}
				if {![string match "*;*" $trimmed]} {
					set pending_signal_line $line
					continue
				}
			}
			if {[regexp {<=} $trimmed] && ![string match "*;*" $trimmed]} {
				set next_code ""
				for {set j [expr {$i + 1}]} {$j < [llength $code_lines]} {incr j} {
					lassign [lindex $code_lines $j] next_line next_raw
					set next_code [string trim $next_raw]
					if {$next_code ne ""} break
				}
				if {[regexp -nocase {^end(\s|;|$)} $next_code]} {
					::aurig::core::analyze::_lint_syntax_error $filename $line "missing semicolon after assignment"
				}
			}

			if {!$in_port_block && [regexp -nocase {^port\s*\(} $trimmed]} {
				set in_port_block 1
				set port_depth [::aurig::core::analyze::_lint_line_paren_delta $trimmed]
				set seen_ports {}
				set previous_port_line 0
				set previous_port_closed 1
				if {$port_depth <= 0} {
					set in_port_block 0
					set port_depth 0
				}
				continue
			}
			if {!$in_port_block && $lower eq "po"} {
				if {$i + 1 < [llength $code_lines]} {
					lassign [lindex $code_lines [expr {$i + 1}]] next_line next_raw
					if {[regexp -nocase {^rt\s*\(} [string trim $next_raw]]} {
						::aurig::core::analyze::_lint_syntax_error $filename $line "keyword port cannot be split across lines"
					}
				}
			}
			if {$in_port_block} {
				set line_delta [::aurig::core::analyze::_lint_line_paren_delta $trimmed]
				set is_port_decl [regexp -nocase {^([A-Za-z][A-Za-z0-9_]*)\s*:\s*([A-Za-z][A-Za-z0-9_]*)(.*)$} $trimmed -> port_name port_mode rest]
				if {$previous_port_line > 0 && !$previous_port_closed && !$is_port_decl && [string match "*;*" $trimmed]} {
					set previous_port_line 0
					set previous_port_closed 1
				}
				if {$is_port_decl} {
					if {$previous_port_line > 0 && !$previous_port_closed} {
						::aurig::core::analyze::_lint_syntax_error $filename $previous_port_line "missing semicolon between port declarations"
					}
					if {[lsearch -exact $seen_ports [string tolower $port_name]] >= 0} {
						::aurig::core::analyze::_lint_syntax_error $filename $line "duplicate port name '$port_name'"
					}
					lappend seen_ports [string tolower $port_name]
					switch -- [string tolower $port_mode] {
						in - out - inout - buffer {}
						default {
							::aurig::core::analyze::_lint_syntax_error $filename $line "invalid port direction '$port_mode'"
						}
					}
					if {[string trim $rest] eq "" || [regexp {^\s*;} $rest]} {
						::aurig::core::analyze::_lint_syntax_error $filename $line "missing port type"
					}
					set previous_port_line $line
					set previous_port_closed [expr {[string match "*;*" $trimmed]}]
				}
				incr port_depth $line_delta
				if {$port_depth <= 0} {
					set in_port_block 0
					set port_depth 0
					set previous_port_line 0
					set previous_port_closed 1
				}
			}
		}
		if {$pending_signal_line > 0} {
			::aurig::core::analyze::_lint_syntax_error $filename $pending_signal_line "missing semicolon after signal declaration"
		}

		set balance 0
		set open_line 1
		foreach pair $code_lines {
			lassign $pair line code
			set len [string length $code]
			for {set i 0} {$i < $len} {incr i} {
				set ch [string index $code $i]
				if {$ch eq "("} {
					incr balance
					set open_line $line
				} elseif {$ch eq ")"} {
					incr balance -1
					if {$balance < 0} {
						::aurig::core::analyze::_lint_syntax_error $filename $line "unmatched closing parenthesis"
					}
				}
			}
		}
		if {$balance > 0} {
			::aurig::core::analyze::_lint_syntax_error $filename $open_line "missing closing parenthesis"
		}

		set entity_stack {}
		set architecture_stack {}
		foreach pair $code_lines {
			lassign $pair line code
			set trimmed [string trim $code]
			if {[regexp -nocase {^entity\s+([A-Za-z][A-Za-z0-9_]*)\s+is(\s|$)} $trimmed -> entity_name]} {
				lappend entity_stack [list $line [string tolower $entity_name]]
			} elseif {[regexp -nocase {^end\s+entity(\s|;|$)} $trimmed]} {
				if {[llength $entity_stack] > 0} {
					set entity_stack [lrange $entity_stack 0 end-1]
				}
			} elseif {[regexp -nocase {^end\s+([A-Za-z][A-Za-z0-9_]*)\s*;} $trimmed -> end_name] &&
				[llength $entity_stack] > 0 &&
				[string tolower $end_name] eq [lindex [lindex $entity_stack end] 1]} {
				set entity_stack [lrange $entity_stack 0 end-1]
			} elseif {[regexp -nocase {^end\s*;} $trimmed] && [llength $entity_stack] > 0 && [llength $architecture_stack] == 0} {
				set entity_stack [lrange $entity_stack 0 end-1]
			}
			if {[regexp -nocase {^architecture\s+([A-Za-z][A-Za-z0-9_]*)\s+of\s+[A-Za-z][A-Za-z0-9_]*\s+is(\s|$)} $trimmed -> architecture_name]} {
				lappend architecture_stack [list $line [string tolower $architecture_name]]
			} elseif {[regexp -nocase {^end\s+architecture(\s|;|$)} $trimmed]} {
				if {[llength $architecture_stack] > 0} {
					set architecture_stack [lrange $architecture_stack 0 end-1]
				}
			} elseif {[regexp -nocase {^end\s+([A-Za-z][A-Za-z0-9_]*)\s*;} $trimmed -> end_name] &&
				[llength $architecture_stack] > 0 &&
				[string tolower $end_name] eq [lindex [lindex $architecture_stack end] 1]} {
				set architecture_stack [lrange $architecture_stack 0 end-1]
			} elseif {[regexp -nocase {^end\s*;} $trimmed] && [llength $architecture_stack] > 0} {
				set architecture_stack [lrange $architecture_stack 0 end-1]
			}
		}
		if {[llength $entity_stack] > 0} {
			::aurig::core::analyze::_lint_syntax_error $filename [lindex [lindex $entity_stack end] 0] "missing end entity"
		}
		if {[llength $architecture_stack] > 0} {
			::aurig::core::analyze::_lint_syntax_error $filename [lindex [lindex $architecture_stack end] 0] "missing end architecture"
		}
	}

	proc vhdlscan {args} {

		set verbose 0
		set vhdFile ""
		set lint "false"
		# parse arguments
		### get user inputs ###
		foreach {switch value} $args {
			switch -- $switch {
				"-v" -
				"-verbosity" {
					set verbose $value
				}
				"-in" {
					set vhdFile $value
				}
				"-lint" {
					set lint $value
				}
			}
		}

		# check if the input file is provided
		if {$vhdFile eq ""} {
			error "ERROR: No input file provided. Use -in <file> to specify the input VHDL file."
			return
		} elseif {![file exists $vhdFile]} {
			error "ERROR: File not found $vhdFile"
			return
		} elseif {![file isfile $vhdFile]} {
			error "ERROR: Input file is not a regular file: $vhdFile"
			return
		}

		set lint_enabled [::aurig::core::analyze::_lint_enabled $lint]
		set lint [expr {$lint_enabled ? "true" : "false"}]

		# welcome message - only show for verbosity >= 1
		if {$verbose >= 1} {
			if {$lint_enabled} {set lint_msg "active"} else {set lint_msg "not active"}
			set systemTime [clock seconds]
			puts "ACARSER: VHDL parser, parsing input file $vhdFile, verbosity $verbose, linting $lint_msg"
			puts "started [clock format $systemTime -format %D] at [clock format $systemTime -format %H:%M:%S]"
		}

		# initialize dictionary
		# set parseDict [dict create]
		set parseDict [::aurig::core::analyze::init $vhdFile]

		# read input file into a string
		if {[catch {set fh [open $vhdFile r]} err] } {
			error "ERROR: Could not open file $vhdFile: $err"
			return
		}
		set content [read $fh]
		close $fh

		if {$lint_enabled} {
			::aurig::core::analyze::_validate_vhdl_lint_syntax $content $vhdFile
		}

		# init line number
		set linenum 0

		# REMOVE TRAILING WHITESACES FROM EACH LINE
		# split the line in multiple lines
		set records [split $content "\n"]
		set file4parser ""
		foreach rec $records {
			incr linenum
			set code $rec
			set comment ""
			set comment_start [::aurig::core::util::find_vhdl_comment_index $rec]
			if {$comment_start >= 0} {
				if {$comment_start == 0} {
					set onlyCode ""
				} else {
					set onlyCode [string range $rec 0 [expr {$comment_start - 1}]]
				}
				set commentPart [string range $rec [expr {$comment_start + 2}] end]
				# Save trimmed code and comment
				set code [string trim $onlyCode]
				set comment [string trim [::aurig::core::analyze::_mask_vhdl_string_literals $commentPart]]
				# Remove common comment markers (*, +, !, @) from the beginning
				# but keep them if they're part of doxygen syntax like @param, @brief, etc.
				if {[regexp {^[*+!]\s*(.*)$} $comment -> cleanComment]} {
					set comment $cleanComment
				}
				dict set parseDict comments line $linenum comment $comment
			} else {
				# No comment found, restore original
				set code [string trim $rec]
			}

			append file4parser "$code\n"
			# parse comments
			# if {[regexp {^\s*--(.*)} $rec -> comment]} {
			# 	dict set parseDict comments line $linenum comment $comment
			# 	set file4parser $file4parser\n
			# } else {
			# 	set file4parser $file4parser[string trim $rec]\n
			# }
		}

		# Parse header metadata from comments
		parse_header_metadata parseDict

		# init line number
		set linenum 1

		# here start my attempt to parse the vhd file
		# the idea is to use simple regexps
		# i know they are not what people uses today but this is what i know
		# we parse one "statement" at a time:
		# a comment
		# a declaration
		# a process
		# a entity declaration
		# and so on
		# lets try it

		while {[string length $file4parser] > 0} {
			# comments
			# non-greedy regexp, we want to find the first match (TCL seems to use
			# non-greedy if you put a non greedy \s*? at the beginning)
			# to parse multiline comments i searched for a \n without a --


			if {[regexp -nocase -- "$::aurig::core::util::re::re_library_decl" $file4parser -> res libraryName]} {
				if {$verbose >= 2} {puts "library $libraryName at $linenum"}
				parse_library file4parser $res parseDict linenum $libraryName $lint
			} elseif {[regexp -nocase -- "$::aurig::core::util::re::re_library_use" $file4parser -> res libraryName packageUsed suffix]} {
				if {$verbose >= 2} {puts "LIBRARY USE CLAUSE $libraryName.$packageUsed.$suffix at $linenum"}
				parse_library_use file4parser $res parseDict linenum $libraryName $packageUsed $suffix
			} elseif {[regexp -nocase -- "$::aurig::core::util::re::re_package_decl" $file4parser -> res packageName pkgDeclPart] } {
				if {$verbose >= 2} {puts "package $packageName declaration at $linenum"}
				parse_package_decl file4parser $res parseDict linenum $packageName $pkgDeclPart $vhdFile
			} elseif {[regexp -nocase -- "$::aurig::core::util::re::re_package_body" $file4parser -> res packageName pkgBodyPart] } {
				if {$verbose >= 2} {puts "package body of $packageName at $linenum"}
				parse_package_body file4parser $res parseDict linenum $packageName $pkgBodyPart $vhdFile $verbose
			} elseif {[regexp -nocase -- "$::aurig::core::util::re::re_entity" $file4parser -> res entityName entityHeader ]} {
			if {$verbose >= 1} {puts "Entity $entityName found at $linenum"}
			parse_entity file4parser $res parseDict linenum $entityName $entityHeader $vhdFile $lint $verbose
		} elseif {[regexp -nocase -- "$::aurig::core::util::re::re_architecture" $file4parser -> res architectureName entityName archDeclPart archBody]} {
			if {$verbose >= 1} {puts "Architecture $architectureName found at $linenum"}
				# split declarative/body reliably
				set S [::aurig::core::analyze::split_arch_decl_body $res]
				set archDeclPart [dict get $S decl]
				set archBody     [dict get $S body]
				set endTail      [dict get $S end_tail]
				parse_architecture file4parser $res parseDict linenum $architectureName $entityName $archDeclPart $archBody $vhdFile
			} else {
				# parse a single line
				regexp {(.*?)\n} $file4parser -> res
				incr linenum
				# update line counter and trim file string of the parsed part
				update_buffer file4parser 1
			}
			## update line counter and trim file string of the parsed part
			#set lineincr [expr {[update_line $res] + 1}]
			#set linenum  [expr {$linenum + $lineincr}]
			#set file4parser [update_buffer $file4parser $lineincr]

		}
		return $parseDict
	}


	proc parse_declarative_part {parseDict declarative_part lint verbose n {commentDict {}} {context "architecture"}} {
		#upvar 1 $linenum n
		upvar 1 $parseDict localDict

		# Determine which add function to use based on context
		if {$context eq "package"} {
			set add_decl_func "::aurig::core::analyze::add_decl_pkg"
		} else {
			set add_decl_func "::aurig::core::analyze::add_decl"
		}

		# scan for signals declarations
		set sig_dict [::aurig::core::analyze::_scan_architecture_signals $declarative_part $n $commentDict]
		# update dictionary
		foreach item $sig_dict {
			set l_list {}
			lappend l_list type [dict get $item type]
			lappend l_list init [dict get $item init]
			if {[dict exists $item comment]} {
				lappend l_list comment [dict get $item comment]
			}
			{*}$add_decl_func localDict "signal" [dict get $item name] [dict get $item line] {*}$l_list
		}
		# scan for variables declarations
		set var_dict [::aurig::core::analyze::_scan_architecture_variables $declarative_part $n]
		# update dictionary
		foreach item $var_dict {
			set l_list {}
			lappend l_list type [dict get $item type]
			lappend l_list init [dict get $item init]
			lappend l_list
			{*}$add_decl_func localDict "variable" [dict get $item name] [dict get $item line] {*}$l_list
		}
		# scan  for constants declarations
		set const_dict [::aurig::core::analyze::_scan_architecture_constants $declarative_part $n $commentDict]
		# update dictionary
		foreach item $const_dict {
			set l_list {}
			lappend l_list type [dict get $item type]
			lappend l_list init [dict get $item init]
			if {[dict exists $item comment]} {
				lappend l_list comment [dict get $item comment]
			}
			lappend l_list
			{*}$add_decl_func localDict "constant" [dict get $item name] [dict get $item line] {*}$l_list
		}

		# scan for function declarations
		set func_dict [::aurig::core::analyze::_scan_functions $declarative_part $n $commentDict]
		# update dictionary
		foreach item $func_dict {
			set l_list {}
			lappend l_list return [dict get $item return]
			lappend l_list params [dict get $item params]
			lappend l_list purity [dict get $item purity]
			if {[dict exists $item comment]} {
				lappend l_list comment [dict get $item comment]
			}
			if {[dict exists $item body_declarations]} {
				lappend l_list body_declarations [dict get $item body_declarations]
			}
			lappend l_list
			{*}$add_decl_func localDict "function" [dict get $item name] [dict get $item line] {*}$l_list
		}

		# scan for type and subtype declarations (LINT-PARSER-DEBT-022)
		set type_dict [::aurig::core::analyze::_scan_architecture_types $declarative_part $n $commentDict]
		foreach item $type_dict {
			set l_list {}
			if {[dict exists $item subtype_kind]} {
				lappend l_list subtype_kind [dict get $item subtype_kind]
			}
			lappend l_list
			{*}$add_decl_func localDict [dict get $item kind] [dict get $item name] [dict get $item line] {*}$l_list
		}

		# scan for procedure declarations
		set proc_dict [::aurig::core::analyze::_scan_procedures $declarative_part $n $commentDict]
		# update dictionary
		foreach item $proc_dict {
			set l_list {}
			lappend l_list params [dict get $item params]
			if {[dict exists $item comment]} {
				lappend l_list comment [dict get $item comment]
			}
			if {[dict exists $item body_declarations]} {
				lappend l_list body_declarations [dict get $item body_declarations]
			}
			lappend l_list
			{*}$add_decl_func localDict "procedure" [dict get $item name] [dict get $item line] {*}$l_list
		}


	}

	#the parseGenerics procedure expects a "port" construct in the input text string, which is the case with entity or component declarations, might not be te case with testbenches
	proc parseGenerics {text} {
		if {[regexp -nocase {[\s\n]*?generic[\s\n]*\((.*)(?:\)[\s\n]*;[\s\n]*port|\)[\s\n]*;[\s\n]*end)} $text -> genericList]} {
			# Split by ; but include preceding comments
			# First, find all generics with any preceding comment lines
			set generics {}
			set lines [split $genericList "\n"]
			set current_item ""

			foreach line $lines {
				set trimmed [string trim $line]
				# If line is a comment or part of declaration, accumulate
				if {$trimmed ne ""} {
					append current_item $line "\n"
				}
				# If line ends with semicolon, we have a complete declaration
				if {[string match "*;*" $trimmed]} {
					lappend generics [string trimright $current_item]
					set current_item ""
				}
			}
			# Handle last item if no trailing semicolon
			if {[string trim $current_item] ne ""} {
				lappend generics [string trimright $current_item]
			}
		} else {
			set generics ""
		}
		return $generics
	}

	#the parsePort procedure expects a "end" construct in the input text string, which is the case with entity or component declarations
	# Note: Empty entities (no generics, no ports) are valid VHDL, commonly used in testbenches
	proc parsePorts {text} {
		# Check if port list exists; if not, return empty list
		# This handles valid empty entity declarations (no generics, no ports)
		if {[regexp -nocase -- "$::aurig::core::util::re::re_port_list" $text -> portList]} {
			# Split by ; but include preceding comments
			set ports {}
			set lines [split $portList "\n"]
			set current_item ""

			foreach line $lines {
				set trimmed [string trim $line]
				# If line is a comment or part of declaration, accumulate
				if {$trimmed ne ""} {
					append current_item $line "\n"
				}
				# If line ends with semicolon or is last port (before closing paren)
				if {[string match "*;*" $trimmed] || [string match "*)*" $trimmed]} {
					lappend ports [string trimright $current_item]
					set current_item ""
				}
			}
			# Handle last item
			if {[string trim $current_item] ne ""} {
				lappend ports [string trimright $current_item]
			}
		} else {
			# No port list found - valid for empty entities
			set ports {}
		}
		return $ports
	}


	proc parse_package_body_content {parseDict package_body lint verbose n} {
			# upvar 1 $linenum n
			upvar 1 $parseDict localDict
			while {[string length $package_body] > 0} {
				# function definition
				if {[regexp -nocase {^((pure[\s\n]+function|impure[\s\n]+function|function)+?[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]+\((.*)\)[\s\n]+return[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]+is[\s\n]+(.*)[\s\n]*begin[\s\n]+(.*)(end|end[\s\n]+function|end[\s\n]+function[\s\n+][a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*;)} $package_body -> res functionType functionName argumentList returnType functDecPart functBody]} {
					if {$lint == true} {
						continue
					} else {
						dict set localDict line $n type "definition" declaration "function" name $functionName args $argumentList returnType $returnType decl_part $functDecPart body $functBody
						if {$verbose >= 3} {
							puts "###"
							puts "function $functionName at line $n"
							puts "arguments : $argumentList"
							puts "return $returnType"
							puts "declarative part : $functDecPart"
							puts "body: $functBody"
							puts "###"
							}
					}
				} elseif {[regexp -nocase {^(procedure[\s\n]+?([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*\((.*)\)[\s\n]+(is[\s\n]+|is[\s\n]+[a-zA-Z0-9_:;\s\n\(\)\'\"=>\+\*\-\/]*)begin[\s\n]+(.*)(end|end[\s\n+][a-zA-Z]+[a-zA-Z0-9_]*|end[\s\n]+procedure|end[\s\n]+procedure[\s\n+][a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*;)} $package_body -> res procedureName argumentList procDecPart procBody]} {
					if {$lint == true} {
						continue
					} else {
						dict set localDict line $n type "definition" declaration "procedure" name $procedureName args $argumentList decl_part $procDecPart body $procBody
					if {$verbose >= 3} {
							puts "###"
							puts "procedure $procedureName at line $n"
							puts "arguments : $argumentList"
							puts "declarative part : $procDecPart"
							puts "body: $procBody"
							puts "###"
							}
					}
				} else {
					# parse a single line
					regexp {(.*?)\n} $package_body -> res
				}
				# # update line counter and trim file string of the parsed part
				set lineincr [expr {[update_line $res] + 1}]
				set n  [expr {$n + $lineincr}]
				update_buffer package_body $lineincr
			}
		}

	proc parse_library {fileBuffer buffer parseDict linenum libraryName lint} {
		# this procedure read the whole current fileBuffer
		# remove the buffer from the beginning of the fileBuffer
		# update parseDict adding a library item
		# <libraries>     <name>          library_name
		# update linenum, considering the parsed lines in buffer
		upvar 1 $linenum n
		upvar 1 $fileBuffer localBuffer
		upvar 1 $parseDict localDict
		# check if libraries entry exists
		# if {![dict exists $localDict libraries]} {
		# 	dict set localDict libraries [dict create]
		# }
		# if {![dict exists $localDict libraries $libraryName]} {
		# 	dict set localDict libraries $libraryName [dict create line $n]
		# }
		::aurig::core::analyze::add_library localDict $libraryName $n $buffer
		# update line counter and trim file string of the parsed part
		set lineincr [expr {[update_line $buffer] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer localBuffer $lineincr
		# if linting is active, check for library name

	}
	proc parse_library_use {fileBuffer buffer parseDict linenum libraryName packageUsed suffix} {
		# this procedure read the whole current fileBuffer
		# remove the buffer from the beginning of the fileBuffer
		# update parseDict adding a library item
		# <libraries>     <name>          library_name
		#				  <use>           packageUsed
		#				  <suffix>		  suffix
		# update linenum, considering the parsed lines in buffer
		upvar 1 $linenum n
		upvar 1 $fileBuffer localBuffer
		upvar 1 $parseDict localDict
		# update dictionary
		::aurig::core::analyze::add_use localDict $libraryName $packageUsed $suffix $n $buffer
		#
		# dict set localDict libraries name $libraryName use $packageUsed
		# dict set localDict libraries name $libraryName suffix $suffix
		# dict set localDict libraries name $libraryName line $n

		# update line counter and trim file string of the parsed part
		set lineincr [expr {[update_line $buffer] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer localBuffer $lineincr

	}
	proc parse_package_decl {fileBuffer buffer parseDict linenum packageName pkgDeclPart filename} {
		# this procedure read the whole current fileBuffer
		# remove the buffer from the beginning of the fileBuffer
		# update parseDict adding a package item
		# <package>       <name>          packageName
		#                 <file>          packageFile
		#                 <declarative>   pkgDeclPart
		# update linenum, considering the parsed lines in buffer
		upvar 1 $linenum n
		upvar 1 $fileBuffer localBuffer
		upvar 1 $parseDict localDict

		# Extract comment dict from localDict for use in parsing
		set commentDict {}
		if {[dict exists $localDict comments line]} {
			set commentDict [dict get $localDict comments line]
		}

		# Calculate the actual starting line of pkgDeclPart
		# The regex captures everything after "package name is", but $n is at "package"
		# We need to count newlines in the buffer up to where pkgDeclPart starts
		# Extract the prefix: everything in buffer before pkgDeclPart
		set pkgDeclStart [string first $pkgDeclPart $buffer]
		if {$pkgDeclStart >= 0} {
			set prefix [string range $buffer 0 [expr {$pkgDeclStart - 1}]]
			set declStartLine [expr {$n + [regexp -all {\n} $prefix]}]
		} else {
			# Fallback if we can't find it (shouldn't happen)
			set declStartLine $n
		}

		# update dictionary using add_package function
		::aurig::core::analyze::add_package localDict $packageName $filename $n $pkgDeclPart
		# extract info from declarative part with comment dict - use corrected line number
		parse_declarative_part localDict $pkgDeclPart false true $declStartLine $commentDict "package"
		# update line counter and trim file string of the parsed part
		set lineincr [expr {[update_line $buffer] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer localBuffer $lineincr

	}

	proc parse_package_body {fileBuffer buffer parseDict linenum packageName pkgBodyPart filename verbose} {
		# this procedure read the whole current fileBuffer
		# remove the buffer from the beginning of the fileBuffer
		# update parseDict adding a package item
		# <package>       <name>          packageName
		#                 <file>          packageFile
		#                 <body>   		  pkgBodyPart
		# update linenum, considering the parsed lines in buffer
		upvar 1 $linenum n
		upvar 1 $fileBuffer localBuffer
		upvar 1 $parseDict localDict
		# search for packageName in the dictionary (should have been defined)
		# if not present create a new instance
		# else update info with the package body

		# Legacy back-compat: keep populating the singular `package_body`
		# top-level dict so existing parser baselines / consumers that
		# expect this shape continue to work. The new structured shape
		# populated below sits at top-level key `package_bodies` (plural
		# list) per analyze/schema.tcl::add_package_body.
		dict set localDict package_body name $packageName
		dict set localDict package_body file_name $filename
		dict set localDict package_body body $pkgBodyPart
		dict set localDict package_body line $n

		# LINT-RULES-DEBT-039: structured surfacing of package-body
		# subprogram declarative-region variables / constants for the
		# lint symbol-builder. Mirror of what `parse_declarative_part`
		# already does for architecture-level subprograms via
		# `_scan_functions` / `_scan_procedures` (LINT-PARSER-DEBT-021):
		# scan the package body for function/procedure DEFINITIONS,
		# extract their `body_declarations` (variable + constant
		# entries from the declarative region between `is` and
		# `begin`), and register each via the schema's
		# `add_function_body_pkg` / `add_procedure_body_pkg` helpers
		# so the entries land in `parse_result.package_bodies`
		# (plural list). The legacy `parse_package_body_content`
		# below is left in place so the singular `package_body` dict
		# and the `line {<N> {type definition ...}}` entries continue
		# to be written, preserving back-compat for existing parser
		# baselines and consumers.
		::aurig::core::analyze::add_package_body localDict $packageName $filename $n $pkgBodyPart
		set pkg_body_commentDict {}
		if {[dict exists $localDict comments line]} {
			set pkg_body_commentDict [dict get $localDict comments line]
		}
		# LINT-RULES-DEBT-039 review: the scanners need the absolute
		# line where $pkgBodyPart STARTS in the source, not the line of
		# the `package body NAME is` header. The captured body group
		# begins AFTER the header `is` (and possibly after blank /
		# comment lines), so passing the header line $n directly would
		# offset all body_declarations earlier by the number of
		# newlines between header and body content — `resolve_location`
		# would then snap repeated local names (e.g. two procedures
		# both declaring `temp`) to the first textual match, giving
		# wrong-line diagnostics. Mirror the prefix-newline-count
		# pattern already used by `parse_package_decl` at L1102-L1109.
		set pkgBodyStart [string first $pkgBodyPart $buffer]
		if {$pkgBodyStart >= 0} {
			set bodyPrefix [string range $buffer 0 [expr {$pkgBodyStart - 1}]]
			set bodyStartLine [expr {$n + [regexp -all {\n} $bodyPrefix]}]
		} else {
			set bodyStartLine $n
		}
		foreach func_item [::aurig::core::analyze::_scan_functions $pkgBodyPart $bodyStartLine $pkg_body_commentDict] {
			set fname       [dict get $func_item name]
			set fline       [dict get $func_item line]
			set fparams     {}
			set freturn     ""
			set fpurity     ""
			set fcomment    ""
			set fbody_decls {}
			if {[dict exists $func_item params]}             { set fparams     [dict get $func_item params] }
			if {[dict exists $func_item return]}             { set freturn     [dict get $func_item return] }
			if {[dict exists $func_item purity]}             { set fpurity     [dict get $func_item purity] }
			if {[dict exists $func_item comment]}            { set fcomment    [dict get $func_item comment] }
			if {[dict exists $func_item body_declarations]}  { set fbody_decls [dict get $func_item body_declarations] }
			::aurig::core::analyze::add_function_body_pkg localDict \
				$fname $fline "" $freturn $fparams $fpurity $fcomment $fbody_decls
		}
		foreach proc_item [::aurig::core::analyze::_scan_procedures $pkgBodyPart $bodyStartLine $pkg_body_commentDict] {
			set pname       [dict get $proc_item name]
			set pline       [dict get $proc_item line]
			set pparams     {}
			set pcomment    ""
			set pbody_decls {}
			if {[dict exists $proc_item params]}             { set pparams     [dict get $proc_item params] }
			if {[dict exists $proc_item comment]}            { set pcomment    [dict get $proc_item comment] }
			if {[dict exists $proc_item body_declarations]}  { set pbody_decls [dict get $proc_item body_declarations] }
			::aurig::core::analyze::add_procedure_body_pkg localDict \
				$pname $pline "" $pparams $pcomment $pbody_decls
		}

		# Legacy raw-text path retained for back-compat (see comment
		# above on the LINT-RULES-DEBT-039 structured path).
		parse_package_body_content localDict $pkgBodyPart false $verbose $n

		# update line counter and trim file string of the parsed part
		set lineincr [expr {[update_line $buffer] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer localBuffer $lineincr

	}

	proc parse_entity {fileBuffer buffer parseDict linenum entityName entityHeader filename lint verbose} {
		# this procedure read the whole current fileBuffer
		# remove the buffer from the beginning of the fileBuffer
		# update parseDict adding a package item
		# <package>       <name>          packageName
		#                 <file>          packageFile
		#                 <body>   		  pkgBodyPart
		# update linenum, considering the parsed lines in buffer
		upvar 1 $linenum n
		upvar 1 $fileBuffer localBuffer
		upvar 1 $parseDict localDict
		# search for packageName in the dictionary (should have been defined)
		# if not present create a new instance
		# else update info with the package body

		# Capture entity comment from previous lines (look back up to 10 lines)
		set entity_comment ""
		if {[dict exists $localDict comments line]} {
			set comment_dict [dict get $localDict comments line]
			for {set i 1} {$i <= 10} {incr i} {
				set check_line [expr {$n - $i}]
				if {[dict exists $comment_dict $check_line]} {
					set cmt [dict get $comment_dict $check_line comment]
					# Skip separator lines
					if {[regexp {^[-=*]{5,}} $cmt]} continue
					# Check for doxygen-style or descriptive comments
					if {[regexp {^[*@]} $cmt] || [string length [string trim $cmt]] > 5} {
						if {$entity_comment ne ""} {
							set entity_comment "$cmt $entity_comment"
						} else {
							set entity_comment $cmt
						}
					} else {
						break
					}
				} else {
					break
				}
			}
		}

		::aurig::core::analyze::begin_entity localDict $entityName $filename $n $entity_comment

		# update dictionary
		# dict set localDict entity name $entityName
		# dict set localDict entity file_name [file normalize [info script]]
		# dict set localDict entity line $n

		# update line counter and trim file string of the parsed part
		set entity_start_line $n
		set lineincr [expr {[update_line $buffer] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer localBuffer $lineincr

		# Build a mapping from generic/port text to their line numbers
		# by counting newlines in the entity header

		set localGenericList [parseGenerics $buffer]
		set localPortList [parsePorts $buffer]
		# set component entry in dictionary
		foreach generic $localGenericList {
			# Count newlines up to this generic to find its approximate line
			# We'll look for a comment in the lines before this generic's line
			set generic_comment ""

			# LINT-PARSER-DEBT-038: default `actual_line` to the captured
			# `$entity_start_line` BEFORE the gen_pos lookup, so a sensible
			# fallback per-generic line is always available for `add_generic`
			# below (the previous code only set `actual_line` inside the
			# `gen_pos >= 0` branch, and the `add_generic` call hard-coded
			# `$n` instead of using the refined per-generic value). With
			# this default + the refinement inside the `if` block, the
			# parser dict's `entity.generics[*].line` now carries the
			# actual per-identifier line rather than a coarser fallback.
			# Critical: the fallback uses `$entity_start_line` (captured
			# at the top of this entity-emit block, line ~1205), NOT `$n`
			# — by this point in the loop `$n` has been advanced past the
			# entity buffer via the `set n [expr {$n + $lineincr}]` at
			# line ~1207, so using `$n` here would report a line AFTER the
			# entity for the gen_pos < 0 edge case (Copilot caught this on
			# PR #101 round 1). Downstream lint diagnostics were OFTEN
			# correct via `lint/lint.tcl::build_symbol_list`'s
			# `resolve_location` name-based forward scan, but that's a
			# best-effort heuristic — not a guarantee — so this fix
			# corrects 22 lint baselines that the heuristic did not catch
			# (and gives downstream raw-dict consumers the right value
			# directly without depending on the heuristic at all).
			set actual_line $entity_start_line

			# Try to extract line number by counting newlines in buffer up to this generic
			set gen_pos [string first [string trim $generic] $buffer]
			if {$gen_pos >= 0} {
				set text_before [string range $buffer 0 $gen_pos]
				set newline_count [regexp -all {\n} $text_before]
				set actual_line [expr {$entity_start_line + $newline_count}]

				# Look for comment on the line before
				if {[dict exists $localDict comments line]} {
					set comment_dict [dict get $localDict comments line]
					for {set i 0} {$i <= 2} {incr i} {
						set check_line [expr {$actual_line - $i}]
						if {[dict exists $comment_dict $check_line]} {
							set cmt [dict get $comment_dict $check_line comment]
							# Skip separator lines and take the first real comment
							if {![regexp {^[-=*]{5,}} $cmt] && [string length [string trim $cmt]] > 0} {
								set generic_comment [string trim $cmt]
								# Remove leading * if present (doxygen style)
								regexp {^\*?\s*(.*)$} $generic_comment -> generic_comment
								break
							}
						}
					}
				}
			}

			# LINT-PARSER-DEBT-037: optionally consume `in` mode keyword
			# between `:` and `<type>`. VHDL allows generics to declare
			# mode (`in` only, since `out`/`inout` generics are exotic
			# VHDL-2008 and not relevant here); most code omits it
			# (mode `in` is the default) but the eo_cpu BFM family
			# (Adc_bfm.vhd:47-48, fileName/readColumn) writes the
			# explicit `: in <type>` form. The original regex did not
			# accept this and silently dropped the generic from the
			# parser's entity.generics list, which surfaced in the
			# 2026-05-24 real-field run as 2 false negatives on
			# `generic_naming`. The new `(?:[iI][nN][\s\n]+)?`
			# non-capturing optional group consumes the mode keyword
			# case-insensitively (VHDL keywords are case-insensitive)
			# when present, leaving the type-name capture intact.
			# Type names that start with `in` (e.g. `integer`,
			# `in_signal_t`) still parse correctly because `[\s\n]+`
			# requires whitespace after the `in` keyword — without
			# whitespace the optional group does not match and the
			# `in`-prefix is left for the type-name capture.
			#
			# Pattern lifted to a local variable to mirror the style of
			# the nearby `port_regex` (~line 1310) — easier to scan and
			# match per-suite changes against the port equivalent.
			set generic_regex {([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*:[\s\n]*(?:[iI][nN][\s\n]+)?([a-zA-Z]+[a-zA-Z0-9_]*|[a-zA-Z]+[a-zA-Z0-9_]*\([a-zA-Z0-9_\'\" \+\*-\/]*\))[\s\n]*(;|:=[\s\n]*([a-zA-Z0-9_'\" =><\+\*-\/\(\)]*)|[\s\n]*$)}
			if {[regexp $generic_regex $generic -> genericName genericType genericInit]} {
				if {$verbose} {puts "GENERICS: name: $genericName, type $genericType, init $genericInit"}
				# grab init value - clean up semicolon-only or empty init
				if {$genericInit eq ";" || $genericInit eq "" || [string trim $genericInit] eq ";"} {
					set genericInitValue ""
				} elseif {[regexp {:=[\s\n]*([a-zA-Z0-9_'" =><\+\*-\/\(\)]*)} $genericInit -> InitValue]} {
					set genericInitValue $InitValue
				} else {
					set genericInitValue ""
				}

				::aurig::core::analyze::add_generic localDict $genericName $genericType $actual_line $genericInitValue $generic_comment
				# dict set localDict line $n type "entity" name $entityName generic $genericName genericType $genericType genericInit $genericInitValue

			}
		}
		foreach port $localPortList {
			# Extract comment similar to generics
			set port_comment ""

			# LINT-PARSER-DEBT-038: default `actual_line` to
			# `$entity_start_line` (NOT `$n` — see the equivalent
			# rationale in the `foreach generic` block above; `$n` has
			# been advanced past the entity buffer by this point in the
			# loop, so it would mis-report the fallback line for the
			# `port_pos < 0` edge case). `add_port` below now passes
			# `$actual_line` instead of `$n`, surfacing the per-port line
			# in the parser dict rather than the entity-start fallback.
			set actual_line $entity_start_line

			set port_pos [string first [string trim $port] $buffer]
			if {$port_pos >= 0} {
				set text_before [string range $buffer 0 $port_pos]
				set newline_count [regexp -all {\n} $text_before]
				set actual_line [expr {$entity_start_line + $newline_count}]

				# Look for comment on the line before
				if {[dict exists $localDict comments line]} {
					set comment_dict [dict get $localDict comments line]
					for {set i 0} {$i <= 2} {incr i} {
						set check_line [expr {$actual_line - $i}]
						if {[dict exists $comment_dict $check_line]} {
							set cmt [dict get $comment_dict $check_line comment]
							# Skip separator lines and take the first real comment
							if {![regexp {^[-=*]{5,}} $cmt] && [string length [string trim $cmt]] > 0} {
								set port_comment [string trim $cmt]
								# Remove leading * if present (doxygen style)
								regexp {^\*?\s*(.*)$} $port_comment -> port_comment
								break
							}
						}
					}
				}
			}

			# parse port item - modified regex to allow optional semicolon for last port
			set port_regex {([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*:[\s\n]*(in|out|inout|buffer)[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*|[a-zA-Z]+[a-zA-Z0-9_]*\([a-zA-Z0-9_'\" \+\*-\/]*\))[\s\n]*(;|:=[\s\n]*([a-zA-Z0-9_'" =><\+\*-\/\(\)]*)|[\s\n]*$)}
			if {[regexp $port_regex $port -> portName portMode portType portInit]} {
				# Clean up port init value
				if {$portInit eq ";" || $portInit eq "" || [string trim $portInit] eq ";"} {
					set portInitValue ""
				} elseif {[regexp {:=[\s\n]*([a-zA-Z0-9_'" =><\+\*-\/\(\)]*)} $portInit -> InitValue]} {
					set portInitValue $InitValue
				} else {
					set portInitValue ""
				}
				::aurig::core::analyze::add_port localDict $portName $portMode $portType $actual_line $portInitValue $port_comment
				# dict set localDict line $n type "entity" name $entityName port $portName portMode $portMode portType $portType portInit $portInit
				if {$verbose} {puts "PORTS: name: $portName, mode: $portMode, type: $portType, init: $portInit"}
			}
		}
		# end entity
		::aurig::core::analyze::end_entity localDict
	}

	proc parse_architecture {fileBuffer buffer parseDict linenum architectureName entityName archDeclPart archBody filename} {
		# this procedure read the whole current fileBuffer
		# remove the buffer from the beginning of the fileBuffer
		# update parseDict adding a package item
		# <architecture>  <name>          arch_name
		# 				  <entity>        name of associated entity
		#                 <decl_section>  declaration_section
		#                 <body_section>  arch_body_section
		# update linenum, considering the parsed lines in buffer
		upvar 1 $linenum n
		upvar 1 $fileBuffer localBuffer
		upvar 1 $parseDict localDict
		# search for packageName in the dictionary (should have been defined)
		# if not present create a new instance
		# else update info with the package body

		# Extract comment dict from localDict for use in parsing
		set commentDict {}
		if {[dict exists $localDict comments line]} {
			set commentDict [dict get $localDict comments line]
		}

		# update dictionary
		# dict set localDict architecture $architectureName
		# dict set localDict architecture $architectureName file_name [file normalize [info script]]
		# dict set localDict architecture $architectureName entity $entityName
		# dict set localDict architecture $architectureName archDeclPart $archDeclPart
		# dict set localDict architecture $architectureName archBody $archBody
		# dict set localDict architecture $architectureName line $n

		::aurig::core::analyze::add_architecture localDict $architectureName $entityName $filename $n $archDeclPart $archBody

		# parse declarative part with comment dict
		parse_declarative_part localDict $archDeclPart false true $n $commentDict
		# update line number
		set lineincr [expr {[update_line $archDeclPart] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer localBuffer $lineincr

		# parse architecture body
		parse_architecture_body localDict $archBody $n

		# update line counter and trim file string of the parsed part
		set lineincr [expr {[update_line $archBody] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer localBuffer $lineincr
	}

	proc match_parenthesis {instring} {

		# the procedure return a string from the first opening parenthesis to the corresponding closing one
		# it can be used to parse procedures, functions, entities, components declarations
		# the regex matching \(((.*)\); cant be used as fìlter might be a port with std_logic_vector(1 downto ); in between
		# and the non-greedy regexp might fail

		# serahc indexes of the opening parenthesis in the input string
		set b [regexp -all -indices -inline \\( $instring]
		# the closing ones
		set c [regexp -all -indices -inline \\) $instring]

		# initialize with all zeros, then put a +1 when a parenthesis is opened and a -1 when it is closed
		set n [split [string repeat 0 [string length $instring]] {}]
		foreach x $b { lset n [lindex $x 0] +1 }
		foreach x $c { lset n [lindex $x 0] -1 }

		# increase a counter when a +1 is detected, decrease it when a -1 is encountered
		# is this way we might find parenthesis matching looking at zeros
		set l 0
		set r {}
		foreach x $n {
			append r [incr l $x]
		}

		# search from first parenthesis to end
		set r_cut [string range $r [string first 1 $r] [string length $r]]
		set stop_idx_tmp [string first 0 $r_cut]
		set first_par_indx [string first 1 $r]
		set res [string range $instring 0 [expr $stop_idx_tmp + $first_par_indx]]
		set rem [string range $instring [expr $stop_idx_tmp + $first_par_indx + 1] [string length $instring]]
		set close_idx [string first ";" $rem]
		return [string range $instring 0 [expr $stop_idx_tmp + $first_par_indx + $close_idx + 1]]

	}

	# update line counter, counts the number of \n in the parsed string
	# and update line counter accordingly
	proc update_line {string} {
		set parsed_lines [llength [regexp -inline -all \n $string]]
		return $parsed_lines
	}

	# trim the parsed string from the file buffer
	proc update_buffer {buffer n} {
		upvar 1 $buffer localBuffer
		set trimmed [join [lrange [split [string trimright $localBuffer] \n] $n end] \n]
		set localBuffer $trimmed
	}

	proc update_parse {buffer sub_buffer linenum} {
		upvar 1 $linenum n
		upvar 1 $buffer buf
		# update line counter and trim file string of the parsed part
		set lineincr [expr {[update_line $sub_buffer] + 1}]
		set n  [expr {$n + $lineincr}]
		update_buffer buf $lineincr
	}

	proc isDict {arg} {
		if {[catch {dict size $arg}]} {
			return 0  ;# Not a valid dictionary
		}
		return 1  ;# Valid dictionary
	}

	proc print_dict {my_dict {nest_level 0} {verbosity 1}} {
		# this procedure prints in a readable text file the result of the parsing
		# of the vhd file.
		# Usage: print_dict dictionaryValue ?nest_level? ?verbosity?
		# where dictionaryValue is the result of parsing, passed by value
		# verbosity: controls output level (default 1)

		# check if argument is a dictionary
		if {![isDict $my_dict]} {
			error "ERROR: argument is not a dictionary"
			return
		}

		# loop over the dictionary and pretty print it
		# if the dictionary is nested, call the procedure recursively
		# set counter to add a tab for each nested dictionary
		set counter $nest_level
		foreach key [dict keys $my_dict] {
			set value [dict get $my_dict $key]
			if {[isDict $value]} {
				incr counter
				if {$verbosity >= 3} {
					puts "[string repeat - $counter] Key: $key"
				}
				print_dict $value $counter $verbosity
			} else {
				if {$verbosity >= 3} {
					puts "[string repeat - $counter]$key: $value"
				}
			}
		}
	}

	#--- Export the procedures ---
	namespace export vhdlscan

}
