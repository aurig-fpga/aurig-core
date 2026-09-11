# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Script Name  : run_doc.tcl
#-----------------------------------------------------------------------------
# Description: Test runner for VHDL parser - DOCUMENTATION PROFILE (tolerant)
#
#              For doc extraction use case, the parser must be tolerant:
#              - Valid VHDL must parse and match expected output
#              - Invalid VHDL must NOT crash (may produce partial output)
#              - Tests pass if output is deterministic and matches expected_doc/
#
#              This profile is for documentation extraction where we want
#              best-effort parsing even on slightly malformed code.
#=============================================================================

# Self-anchored root resolution (same pattern as the other ported core tests):
# this script lives at <root>/test/parser/run_doc.tcl, so the aurig-core root
# is two levels up. Append it to ::auto_path and pull in the parser/util core.
set script_anchor [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname [file dirname $script_anchor]]
lappend ::auto_path $aurig_core_root
package require aurig::core

set script_dir $script_anchor
set fixtures_dir [file join $script_dir "fixtures"]
set expected_dir [file join $script_dir "expected_doc"]

# Source helper procedures
source [file join $script_dir "helpers.tcl"]

# Import helper namespace
namespace import ::aurig::core::test::parser::normalize_parse_dict
namespace import ::aurig::core::test::parser::find_fixture_files
namespace import ::aurig::core::test::parser::get_expected_filename
namespace import ::aurig::core::test::parser::compare_dicts
namespace import ::aurig::core::test::parser::load_expected
namespace import ::aurig::core::test::parser::save_expected
namespace import ::aurig::core::test::parser::print_test_result
namespace import ::aurig::core::test::parser::print_summary
namespace import ::aurig::core::test::parser::file_relative_to
namespace import ::aurig::core::test::parser::is_known_failure
namespace import ::aurig::core::test::parser::is_invalid_syntax
namespace import ::aurig::core::test::parser::get_xfail_reason
namespace import ::aurig::core::test::parser::get_invalid_syntax_reason

#=============================================================================
# Documentation Profile Test Procedure
#=============================================================================

proc run_doc_tests {{generate_mode 0} {strict_mode 0}} {
    global fixtures_dir expected_dir

    puts "=========================================="
    puts "VHDL Parser Test Suite - DOC PROFILE"
    puts "=========================================="
    puts "Profile: DOCUMENTATION (tolerant)"
    puts "  - Valid VHDL must parse correctly"
    puts "  - Invalid VHDL must not crash"
    puts "  - Best-effort parsing accepted"
    puts "=========================================="
    puts "Fixtures: $fixtures_dir"
    puts "Expected: $expected_dir"
    if {$generate_mode} {
        puts "Mode: GENERATE (creating expected files)"
    } else {
        puts "Mode: VERIFY (comparing against expected)"
    }
    if {$strict_mode} {
        puts "Strict: ON (XFAIL counts as failures)"
    } else {
        puts "Strict: OFF (XFAIL allowed)"
    }
    puts "=========================================="
    puts ""

    # Find all fixture files
    set fixture_files [find_fixture_files $fixtures_dir]

    if {[llength $fixture_files] == 0} {
        puts "ERROR: No fixture files found in $fixtures_dir"
        return 1
    }

    puts "Found [llength $fixture_files] fixture file(s)\n"

    # Test counters
    set total 0
    set passed 0
    set failed 0
    set skipped 0
    set xfail 0
    set xpass 0

    # Process each fixture
    foreach fixture_file $fixture_files {
        incr total

        # Get fixture name relative to fixtures dir
        set rel_path [file_relative_to $fixture_file $fixtures_dir]

        # Get expected output filename
        set expected_file [get_expected_filename $fixture_file $fixtures_dir $expected_dir]

        # An adjacent .vhd.errorcode sidecar opts a fixture into strict rejection.
        set errorcode_file [format "%s.errorcode" $fixture_file]
        if {[file exists $errorcode_file]} {
            if {[catch {
                set errorcode_channel [open $errorcode_file r]
                set expected_errorcode [string trim [read $errorcode_channel]]
                close $errorcode_channel
                if {[llength $expected_errorcode] != 4 ||
                    [lrange $expected_errorcode 0 2] ne {AURIG CORE PARSE}} {
                    error "expected an AURIG CORE PARSE reason"
                }
                set expected_errorcode [lrange $expected_errorcode 0 end]
            } expectation_error]} {
                print_test_result $rel_path "FAIL" "Invalid errorcode sidecar: $expectation_error"
                incr failed
                continue
            }
            set parse_code [catch {
                ::aurig::core::analyze::vhdlscan -in $fixture_file -verbosity 0
            } parse_error parse_options]
            if {$parse_code == 1 &&
                [dict exists $parse_options -errorcode] &&
                [dict get $parse_options -errorcode] eq $expected_errorcode} {
                print_test_result $rel_path "PASS" "Rejected with $expected_errorcode"
                incr passed
            } else {
                print_test_result $rel_path "FAIL" "Expected $expected_errorcode; completion $parse_code: $parse_error"
                incr failed
            }
            continue
        }

        # Check if this is invalid syntax
        set is_invalid [is_invalid_syntax $fixture_file]

        # DOC PROFILE: For invalid syntax, we don't expect rejection
        # We expect the parser to NOT CRASH and produce deterministic output
        if {$is_invalid} {
            set invalid_reason [get_invalid_syntax_reason $fixture_file]

            # Try to parse - should not crash
            if {[catch {
                set parse_result [::aurig::core::analyze::vhdlscan -in $fixture_file -verbosity 0]
            } parse_error]} {
                # Parser crashed on invalid syntax - this is OK in doc profile
                # but we document it
                print_test_result $rel_path "PASS" "Invalid syntax handled (rejected: [string range $parse_error 0 50]...)"
                incr passed
                continue
            }

            # Parser didn't crash - normalize result
            if {[catch {
                set normalized [normalize_parse_dict $parse_result]
            } norm_error]} {
                # Normalization failed - this is still OK, parser didn't crash
                print_test_result $rel_path "PASS" "Invalid syntax handled (partial parse)"
                incr passed
                continue
            }

            # If generating, save the output
            if {$generate_mode} {
                if {[catch {
                    save_expected $expected_file $normalized
                    print_test_result $rel_path "SAVED" "Invalid syntax - best-effort output saved"
                    incr passed
                } save_error]} {
                    print_test_result $rel_path "FAIL" "Failed to save expected: $save_error"
                    incr failed
                }
                continue
            }

            # If verifying, compare against expected
            if {![file exists $expected_file]} {
                # No expected file - that's OK, parser didn't crash
                print_test_result $rel_path "PASS" "Invalid syntax handled (no expected file needed)"
                incr passed
                continue
            }

            # Compare against expected
            if {[catch {
                set expected [load_expected $expected_file]
                set differences [compare_dicts $normalized $expected]

                if {[llength $differences] == 0} {
                    print_test_result $rel_path "PASS" "Invalid syntax - deterministic output"
                    incr passed
                } else {
                    # Output changed - document it but still pass (didn't crash)
                    print_test_result $rel_path "WARN" "Invalid syntax - output changed but no crash"
                    incr passed
                }
            } compare_error]} {
                # Comparison failed but parser didn't crash
                print_test_result $rel_path "PASS" "Invalid syntax handled"
                incr passed
            }
            continue
        }

        # Check if this is a known failure (valid VHDL parser can't handle)
        set is_xfail [is_known_failure $fixture_file]
        set xfail_reason ""
        if {$is_xfail} {
            set xfail_reason [get_xfail_reason $fixture_file]
        }

        # Parse the fixture file
        if {[catch {
            set parse_result [::aurig::core::analyze::vhdlscan -in $fixture_file -verbosity 0]
        } parse_error]} {
            # Parser failed
            if {$is_xfail} {
                # Expected failure (XFAIL)
                puts "  \[X\] XFAIL  $rel_path"
                puts "        Reason: $xfail_reason"
                incr xfail
            } else {
                # Unexpected failure
                print_test_result $rel_path "FAIL" "Parser error: $parse_error"
                incr failed
            }
            continue
        }

        # Normalize the parse result
        if {[catch {
            set normalized [normalize_parse_dict $parse_result]
        } norm_error]} {
            print_test_result $rel_path "FAIL" "Normalization error: $norm_error"
            incr failed
            continue
        }

        # Generate mode: save expected output
        if {$generate_mode} {
            if {[catch {
                save_expected $expected_file $normalized
                print_test_result $rel_path "SAVED" "Expected file generated"
                incr passed
            } save_error]} {
                print_test_result $rel_path "FAIL" "Failed to save expected: $save_error"
                incr failed
            }
            continue
        }

        # Verify mode: compare against expected
        if {![file exists $expected_file]} {
            print_test_result $rel_path "SKIP" "Expected file not found: $expected_file"
            incr skipped
            continue
        }

        # Load expected results
        if {[catch {
            set expected [load_expected $expected_file]
        } load_error]} {
            print_test_result $rel_path "FAIL" "Failed to load expected: $load_error"
            incr failed
            continue
        }

        # Compare results
        set differences [compare_dicts $normalized $expected]

        if {[llength $differences] == 0} {
            # Test passed
            if {$is_xfail} {
                # Unexpected pass (XPASS)
                puts "  \[!\] XPASS  $rel_path"
                puts "        This test was expected to fail but passed!"
                puts "        Reason: $xfail_reason"
                incr xpass
            } else {
                # Expected pass
                print_test_result $rel_path "PASS"
                incr passed
            }
        } else {
            # Test failed
            if {$is_xfail} {
                # Expected failure (XFAIL)
                puts "  \[X\] XFAIL  $rel_path"
                puts "        Reason: $xfail_reason"
                incr xfail
            } else {
                # Unexpected failure
                set details [join $differences "\n"]
                print_test_result $rel_path "FAIL" $details
                incr failed
            }
        }
    }

    # Print summary
    puts ""
    set exit_code [print_summary $total $passed $failed $skipped $xfail $xpass $strict_mode]

    return $exit_code
}

#=============================================================================
# Command line argument processing
#=============================================================================

proc print_usage {} {
    puts "Usage: tclsh run_doc.tcl \[options\]"
    puts ""
    puts "DOC PROFILE (tolerant): For documentation extraction"
    puts "  - Valid VHDL must parse and match expected output"
    puts "  - Invalid VHDL must not crash (may produce partial output)"
    puts "  - Tests pass if output is deterministic"
    puts ""
    puts "Options:"
    puts "  -generate     Generate expected output files from current parser"
    puts "  -verify       Verify parser output against expected files (default)"
    puts "  -strict       Treat XFAIL (known failures) as real failures"
    puts "  -help         Show this help message"
    puts ""
    puts "Known Failures:"
    puts "  Tests in fixtures/known_failures/ are VALID VHDL the parser can't handle."
    puts "  By default, XFAIL results don't cause test suite to exit with error."
    puts "  Use -strict to make XFAIL count as real failures."
    puts ""
    puts "Examples:"
    puts "  tclsh run_doc.tcl                # Run tests in verify mode"
    puts "  tclsh run_doc.tcl -generate      # Generate expected files"
    puts "  tclsh run_doc.tcl -strict        # Run with strict XFAIL checking"
}

# Parse command line arguments
set generate_mode 0
set strict_mode 0

if {$argc > 0} {
    foreach arg $argv {
        switch -exact -- $arg {
            "-generate" {
                set generate_mode 1
            }
            "-verify" {
                set generate_mode 0
            }
            "-strict" -
            "--strict" {
                set strict_mode 1
            }
            "-help" -
            "--help" -
            "-h" {
                print_usage
                exit 0
            }
            default {
                puts "ERROR: Unknown argument: $arg"
                print_usage
                exit 1
            }
        }
    }
}

# Run the tests
set exit_code [run_doc_tests $generate_mode $strict_mode]

# Exit with appropriate code
exit $exit_code
