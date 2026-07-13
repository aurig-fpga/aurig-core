# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Script Name  : helpers.tcl
# Namespace    : ::aurig::core::test::parser
#-----------------------------------------------------------------------------
# Description: Helper procedures for VHDL parser testing
#              Provides normalization, comparison, and test utilities
#=============================================================================

namespace eval ::aurig::core::test::parser {

    # Normalize parsed dictionary for deterministic comparison.
    #
    # Parser output contains both Tcl data structures and raw VHDL text. Raw text
    # can look like a valid Tcl list (for example "library ieee;" or process
    # bodies), so normalization must recurse by schema path, not by guessing from
    # value syntax.
    proc normalize_parse_dict {parseDict} {
        return [normalize_dict_recursive $parseDict {}]
    }

    proc _path_matches {path pattern} {
        if {[llength $path] != [llength $pattern]} {
            return 0
        }
        foreach p $path q $pattern {
            if {$q eq "*"} {
                continue
            }
            if {$p ne $q} {
                return 0
            }
        }
        return 1
    }

    proc _container_kind {path} {
        set struct_paths {
            {}
            {meta}
            {metadata}
            {comments}
            {comments line *}
            {libraries *}
            {uses *}
            {entities *}
            {entities * generics *}
            {entities * ports *}
            {architectures *}
            {architectures * declarations *}
            {architectures * processes *}
            {architectures * instantiations *}
            {architectures * instantiations * generics_map *}
            {architectures * instantiations * ports_map *}
            {architectures * assignments *}
            {architectures * generates *}
            {architectures * blocks *}
            {packages *}
            {packages * declarations *}
            {packages * components *}
            {packages * generics *}
            {packages * ports *}
            {package_bodies *}
            {package_bodies * functions *}
            {package_bodies * procedures *}
            {package_body}
            {line *}
        }
        foreach pattern $struct_paths {
            if {[_path_matches $path $pattern]} {
                return struct
            }
        }

        set list_paths {
            {libraries}
            {uses}
            {entities}
            {entities * generics}
            {entities * ports}
            {architectures}
            {architectures * declarations}
            {architectures * declarations * args}
            {architectures * declarations * generics}
            {architectures * declarations * ports}
            {architectures * processes}
            {architectures * instantiations}
            {architectures * instantiations * generics_map}
            {architectures * instantiations * ports_map}
            {architectures * assignments}
            {architectures * generates}
            {architectures * blocks}
            {packages}
            {packages * declarations}
            {packages * components}
            {packages * generics}
            {packages * ports}
            {package_bodies}
            {package_bodies * functions}
            {package_bodies * procedures}
        }
        foreach pattern $list_paths {
            if {[_path_matches $path $pattern]} {
                return list
            }
        }

        if {[_path_matches $path {comments line}] || [_path_matches $path {line}]} {
            return map
        }
        if {[_path_matches $path {architectures * processes * sensitivity}]} {
            return scalar_list
        }
        return leaf
    }

    proc _normalize_leaf {value path} {
        set key [lindex $path end]
        if {$key eq "filename" || $key eq "file" || $key eq "file_name"} {
            if {[string match "*/*" $value] || [string match "*\\*" $value]} {
                return [file tail $value]
            }
        }
        return $value
    }

    # Recursively normalize only schema-declared containers. Leaf values are
    # atomic by default, even when their text is syntactically a Tcl list.
    proc normalize_dict_recursive {value {path {}}} {
        set kind [_container_kind $path]
        switch -- $kind {
            struct - map {
                if {![string is list $value] || [llength $value] % 2 != 0 || [catch {dict keys $value}]} {
                    return $value
                }
                set result [dict create]
                foreach key [lsort [dict keys $value]] {
                    if {[llength $path] == 1 && [lindex $path 0] eq "meta" && $key ni {file}} {
                        continue
                    }
                    dict set result $key [normalize_dict_recursive [dict get $value $key] [concat $path [list $key]]]
                }
                return $result
            }
            list {
                if {![string is list $value]} {
                    return $value
                }
                set result [list]
                foreach item $value {
                    lappend result [normalize_dict_recursive $item [concat $path [list *]]]
                }
                return $result
            }
            scalar_list {
                return $value
            }
            default {
                return [_normalize_leaf $value $path]
            }
        }
    }

    # Convert dictionary to canonical string format (sorted, indented)
    # for diff-friendly output
    proc dict_to_canonical_string {d {indent 0}} {
        set result ""
        set prefix [string repeat "  " $indent]

        if {![string is list $d] || [llength $d] % 2 != 0} {
            return $d
        }

        if {[catch {dict keys $d}]} {
            return $d
        }

        foreach key [lsort [dict keys $d]] {
            set value [dict get $d $key]

            # Check if value is a nested dict
            set is_nested_dict 0
            if {[string is list $value] && [llength $value] % 2 == 0} {
                if {![catch {dict keys $value}]} {
                    set is_nested_dict 1
                }
            }

            if {$is_nested_dict} {
                append result "${prefix}${key} \{\n"
                append result [dict_to_canonical_string $value [expr {$indent + 1}]]
                append result "${prefix}\}\n"
            } else {
                # Escape special characters in value
                set escaped_value [list $value]
                append result "${prefix}${key} ${escaped_value}\n"
            }
        }

        return $result
    }

    # Find all VHDL fixture files recursively
    proc find_fixture_files {fixtures_dir} {
        set files [list]

        # Recursively find all .vhd files
        foreach file [glob -nocomplain -types f [file join $fixtures_dir *.vhd]] {
            lappend files $file
        }

        # Check subdirectories
        foreach dir [glob -nocomplain -types d [file join $fixtures_dir *]] {
            set subfiles [find_fixture_files $dir]
            set files [concat $files $subfiles]
        }

        return [lsort $files]
    }

    # Get the expected output filename for a given fixture
    proc get_expected_filename {fixture_path fixtures_dir expected_dir} {
        # Get relative path from fixtures dir
        set rel_path [file_relative_to $fixture_path $fixtures_dir]

        # Replace .vhd with .expected
        set expected_name [file rootname $rel_path].expected

        # Replace directory separators with underscores to flatten structure
        set expected_name [string map {/ _ \\ _} $expected_name]

        return [file join $expected_dir $expected_name]
    }

    # Calculate relative path
    proc file_relative_to {path base} {
        set path [string map {\\ /} $path]
        set base [string map {\\ /} $base]

        # Convert to lists of path components
        set path_parts [file split $path]
        set base_parts [file split $base]

        # Find common prefix
        set common 0
        foreach p $path_parts b $base_parts {
            if {[string equal -nocase $p $b]} {
                incr common
            } else {
                break
            }
        }

        # Build relative path
        set rel_parts [lrange $path_parts $common end]
        return [eval file join $rel_parts]
    }

    # Compare two dictionaries and return detailed differences
    proc compare_dicts {dict1 dict2 {path ""}} {
        set differences [list]

        # Get all keys from both dicts
        set all_keys [lsort -unique [concat [dict keys $dict1] [dict keys $dict2]]]

        foreach key $all_keys {
            set current_path [expr {$path eq "" ? $key : "${path}.${key}"}]

            set has_key1 [dict exists $dict1 $key]
            set has_key2 [dict exists $dict2 $key]

            if {!$has_key1} {
                lappend differences "Missing in actual: $current_path"
                continue
            }

            if {!$has_key2} {
                lappend differences "Extra in actual: $current_path"
                continue
            }

            set val1 [dict get $dict1 $key]
            set val2 [dict get $dict2 $key]

            # Check if both are dicts
            set is_dict1 0
            set is_dict2 0

            if {[string is list $val1] && [llength $val1] % 2 == 0} {
                if {![catch {dict keys $val1}]} {
                    set is_dict1 1
                }
            }

            if {[string is list $val2] && [llength $val2] % 2 == 0} {
                if {![catch {dict keys $val2}]} {
                    set is_dict2 1
                }
            }

            if {$is_dict1 && $is_dict2} {
                # Recursively compare nested dicts
                set nested_diffs [compare_dicts $val1 $val2 $current_path]
                set differences [concat $differences $nested_diffs]
            } elseif {$val1 ne $val2} {
                lappend differences "Mismatch at $current_path:\n  Expected: $val2\n  Actual:   $val1"
            }
        }

        return $differences
    }

    # Load expected results from file
    proc load_expected {filename} {
        if {![file exists $filename]} {
            error "Expected file not found: $filename"
        }

        set fh [open $filename r]
        set content [read $fh]
        close $fh

        # Content is a Tcl dict; normalize it too so legacy expected files do
        # not encode launch-environment-specific absolute paths.
        return [normalize_parse_dict $content]
    }

    # Parse canonical string format back to dictionary
    proc string_to_dict {content} {
        set result [dict create]
        set lines [split $content "\n"]
        set stack [list $result]
        set key_stack [list]

        foreach line $lines {
            if {[string trim $line] eq ""} continue

            # Count indentation
            set indent [expr {[string length $line] - [string length [string trimleft $line]]}]
            set level [expr {$indent / 2}]
            set trimmed [string trim $line]

            # Handle closing braces
            if {$trimmed eq "\}"} {
                set stack [lrange $stack 0 end-1]
                set key_stack [lrange $key_stack 0 end-1]
                continue
            }

            # Parse key-value or key with nested dict
            if {[regexp {^(\S+)\s+\{$} $trimmed -> key]} {
                # Start of nested dict
                set new_dict [dict create]
                dict set [lindex $stack end] $key $new_dict
                lappend stack $new_dict
                lappend key_stack $key
            } elseif {[regexp {^(\S+)\s+(.+)$} $trimmed -> key value]} {
                # Key-value pair - eval to unescape
                if {[catch {set actual_value [eval list $value]}]} {
                    set actual_value $value
                }
                dict set [lindex $stack end] $key $actual_value
            }
        }

        return $result
    }

    # Save expected results to file
    proc save_expected {filename normalized_dict} {
        # Simply save the dict as a Tcl list (most reliable format)
        set fh [open $filename w]
        puts $fh $normalized_dict
        close $fh
    }

    # Print test results in a clear format
    proc print_test_result {fixture_name status {details ""}} {
        set status_str [format "%-6s" $status]

        if {$status eq "PASS"} {
            puts "  \[✓\] $status_str $fixture_name"
        } elseif {$status eq "FAIL"} {
            puts "  \[✗\] $status_str $fixture_name"
            if {$details ne ""} {
                foreach line [split $details "\n"] {
                    puts "        $line"
                }
            }
        } else {
            puts "  \[?\] $status_str $fixture_name"
            if {$details ne ""} {
                puts "        $details"
            }
        }
    }

    # Summary report
    proc print_summary {total passed failed skipped {xfail 0} {xpass 0} {strict_mode 0}} {
        puts "\n=========================================="
        puts "Test Summary"
        puts "=========================================="
        puts "Total:   $total"
        puts "Passed:  $passed"
        puts "Failed:  $failed"
        if {$xfail > 0} {
            puts "XFail:   $xfail (expected failures)"
        }
        if {$xpass > 0} {
            puts "XPass:   $xpass (unexpected passes)"
        }
        puts "Skipped: $skipped"
        puts "=========================================="

        # In strict mode, XFAIL counts as real failures
        set effective_failures $failed
        if {$strict_mode} {
            set effective_failures [expr {$failed + $xfail}]
        }

        if {$effective_failures == 0 && $xpass == 0} {
            puts "✓ All tests passed!"
            return 0
        } elseif {!$strict_mode && $failed == 0 && $xfail > 0 && $xpass == 0} {
            puts "✓ All tests passed (with $xfail known failures)"
            return 0
        } else {
            if {$xpass > 0} {
                puts "⚠ Some tests unexpectedly passed (XPASS)!"
            }
            if {$effective_failures > 0} {
                puts "✗ Some tests failed."
            }
            return 1
        }
    }

    # Check if a fixture is a known failure
    proc is_known_failure {fixture_path} {
        set normalized_path [file normalize $fixture_path]
        return [string match "*known_failures*" $normalized_path]
    }

    # Check if a fixture is invalid syntax (should be rejected by parser)
    proc is_invalid_syntax {fixture_path} {
        set normalized_path [file normalize $fixture_path]
        return [string match "*invalid_syntax*" $normalized_path]
    }

    # Extract XFAIL reason from fixture file
    proc get_xfail_reason {fixture_path} {
        set fh [open $fixture_path r]
        set first_line [gets $fh]
        close $fh

        # Look for XFAIL: marker in first line
        if {[regexp {^--\s*XFAIL:\s*(.+)$} $first_line -> reason]} {
            return [string trim $reason]
        }

        return "No reason specified"
    }

    # Extract invalid syntax reason from fixture file
    proc get_invalid_syntax_reason {fixture_path} {
        set fh [open $fixture_path r]
        set first_line [gets $fh]
        close $fh

        # Look for INVALID_SYNTAX: marker in first line
        if {[regexp {^--\s*INVALID_SYNTAX:\s*(.+)$} $first_line -> reason]} {
            return [string trim $reason]
        }

        return "Invalid VHDL syntax"
    }

    # Print XFAIL result
    proc print_xfail_result {fixture_name reason} {
        puts "  \[X\] XFAIL  $fixture_name"
        puts "        Reason: $reason"
    }

    # Print XPASS result
    proc print_xpass_result {fixture_name reason} {
        puts "  \[!\] XPASS  $fixture_name"
        puts "        This test was expected to fail but passed!"
        puts "        Reason: $reason"
    }

    # Print invalid syntax result (parser correctly rejected)
    proc print_invalid_syntax_pass {fixture_name reason} {
        puts "  \[✓\] PASS   $fixture_name (invalid syntax rejected)"
    }

    # Print invalid syntax failure (parser accepted invalid syntax)
    proc print_invalid_syntax_fail {fixture_name reason} {
        puts "  \[✗\] FAIL   $fixture_name"
        puts "        Parser accepted invalid VHDL syntax (should reject)"
        puts "        Reason: $reason"
    }

    # Verify comment association for a specific declaration
    # Returns 1 if comment exists, 0 if not
    # This helper can be used for custom assertions about comment presence
    proc has_comment {parsed_dict path_list} {
        set current $parsed_dict

        # Navigate through the path
        foreach key $path_list {
            if {![dict exists $current $key]} {
                return 0
            }
            set current [dict get $current $key]
        }

        # Check if current location has a comment field
        if {[string is list $current] && [llength $current] % 2 == 0} {
            if {![catch {dict keys $current}]} {
                # It's a dict, check for comment key
                return [dict exists $current comment]
            }
        }

        return 0
    }

    # Extract comment text from a declaration
    # Returns empty string if no comment exists
    proc get_comment {parsed_dict path_list} {
        set current $parsed_dict

        # Navigate through the path
        foreach key $path_list {
            if {![dict exists $current $key]} {
                return ""
            }
            set current [dict get $current $key]
        }

        # Get comment if it exists
        if {[string is list $current] && [llength $current] % 2 == 0} {
            if {![catch {dict keys $current}]} {
                if {[dict exists $current comment]} {
                    return [dict get $current comment]
                }
            }
        }

        return ""
    }

    namespace export normalize_parse_dict
    namespace export dict_to_canonical_string
    namespace export find_fixture_files
    namespace export get_expected_filename
    namespace export file_relative_to
    namespace export compare_dicts
    namespace export load_expected
    namespace export save_expected
    namespace export print_test_result
    namespace export print_summary
    namespace export has_comment
    namespace export get_comment
    namespace export is_known_failure
    namespace export is_invalid_syntax
    namespace export get_xfail_reason
    namespace export get_invalid_syntax_reason
    namespace export print_xfail_result
    namespace export print_xpass_result
    namespace export print_invalid_syntax_pass
    namespace export print_invalid_syntax_fail
}
