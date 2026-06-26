# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Test: LINT-PROJECT-DEBT-032
#
# `::aurig::core::util::_yaml_parse_scalar` (and via it `readYamlMinimal`) must
# strip inline `#` comments from unquoted scalar values, matching the YAML
# 1.1/1.2 rule that `#` preceded by whitespace introduces a comment to end
# of line. Quoted scalars must preserve `#` as a literal character.
#
# Surfaced by the 2026-05-25 Sentinel real-test pass where a manifest field
#
#     project_root: ../..                  # commento inline esplicativo
#
# was read by the in-tree minimal reader (selected because tcllib's `yaml`
# package was not on `auto_path` for the Windows Git-Bash tclsh that
# happened to win the PATH race) as the full literal string
# `"../..                  # commento inline esplicativo"`. Downstream
# project-root resolution then produced an opaque "Project root not found"
# error citing a non-existent embedded-comment directory.

package require Tcl 8.5

set script_dir [file dirname [file normalize [info script]]]
set aurig_core_root [file dirname $script_dir]
lappend ::auto_path $aurig_core_root
package require aurig::core

set tests_run 0
set tests_passed 0
set tests_failed 0

proc test {name body} {
    global tests_run tests_passed tests_failed
    incr tests_run
    puts -nonewline "  Test: $name ... "
    if {[catch {uplevel 1 $body} result]} {
        incr tests_failed
        puts "FAILED: $result"
        return 0
    } else {
        incr tests_passed
        puts "PASSED"
        return 1
    }
}

proc assert_eq {actual expected {msg ""}} {
    if {$actual ne $expected} {
        if {$msg ne ""} {
            error "$msg: expected '$expected', got '$actual'"
        } else {
            error "Expected '$expected', got '$actual'"
        }
    }
}

puts "============================================================"
puts "LINT-PROJECT-DEBT-032: inline `#` comment stripping in"
puts "                       readYamlMinimal / _yaml_parse_scalar"
puts "============================================================"
puts ""

# =============================================================================
# Suite 1: _yaml_parse_scalar — strict unit coverage of all the cases listed
# in the ticket description plus the quoted-scalar preservation guarantees.
# =============================================================================
puts "Suite 1: _yaml_parse_scalar — direct unit coverage"
puts "--------------------------------------------------"

test "Plain scalar, no comment → unchanged" {
    set result [::aurig::core::util::_yaml_parse_scalar "value"]
    assert_eq $result "value"
}

test "Plain scalar with single-space `# comment` → stripped" {
    set result [::aurig::core::util::_yaml_parse_scalar "value # comment"]
    assert_eq $result "value"
}

test "Plain scalar with multi-space `# comment` → stripped, trailing trim" {
    set result [::aurig::core::util::_yaml_parse_scalar "value          # comment"]
    assert_eq $result "value"
}

test "Plain path with multiple spaces before `#` (the Sentinel case)" {
    set result [::aurig::core::util::_yaml_parse_scalar "../..  # path with multiple spaces before #"]
    assert_eq $result "../.."
}

test "Plain scalar with tab before `#` → stripped" {
    set result [::aurig::core::util::_yaml_parse_scalar "value\t# comment"]
    assert_eq $result "value"
}

test "Plain scalar with `#` NOT preceded by whitespace → preserved" {
    # YAML: `#` is a comment delimiter ONLY when preceded by whitespace.
    # A bare `#` adjacent to other chars is a literal.
    set result [::aurig::core::util::_yaml_parse_scalar "value#nocomment"]
    assert_eq $result "value#nocomment"
}

test "Double-quoted scalar with `#` inside → quotes stripped, `#` preserved" {
    set result [::aurig::core::util::_yaml_parse_scalar {"value # quoted"}]
    assert_eq $result "value # quoted"
}

test "Single-quoted scalar with `#` inside → quotes stripped, `#` preserved" {
    set result [::aurig::core::util::_yaml_parse_scalar {'value # quoted'}]
    assert_eq $result "value # quoted"
}

test "Plain scalar with leading whitespace → trimmed" {
    set result [::aurig::core::util::_yaml_parse_scalar "   value   "]
    assert_eq $result "value"
}

test "Plain scalar with leading whitespace and inline comment" {
    set result [::aurig::core::util::_yaml_parse_scalar "   value   # comment"]
    assert_eq $result "value"
}

test "Quoted scalar with `#` directly after closing quote (no whitespace) is NOT a comment (Copilot PR #85 round-1)" {
    # YAML requires `#` to be preceded by whitespace to count as a
    # comment delimiter. `"x"#tail` is malformed YAML; the parser
    # falls through to the unquoted path which (also requiring `\s+#`)
    # cannot strip anything, so the literal string is returned with
    # quotes intact — defensive non-mangling behaviour, the operator
    # sees an unparseable downstream error rather than silent damage.
    set result [::aurig::core::util::_yaml_parse_scalar {"x"#nocomment}]
    assert_eq $result {"x"#nocomment}
}

test "Single-quoted scalar with doubled apostrophe escape (Copilot PR #85 round-2)" {
    # YAML's single-quoted form escapes an embedded apostrophe by
    # doubling it: `'it''s'` is the YAML way to encode the string
    # `it's`. The pre-round-2 regex `^'([^']*)'$` rejected this
    # outright (the `[^']*` class stopped at the first `'`) and the
    # input fell through to the unquoted path which returned the
    # value with quotes still attached. The round-2 regex
    # `^'((?:[^']|'')*)'...$` accepts the doubled-`''` pair, and the
    # caller collapses `''` back to `'` via `string map`.
    set result [::aurig::core::util::_yaml_parse_scalar {'it''s'}]
    assert_eq $result {it's}
}

test "Single-quoted scalar with doubled apostrophe + trailing comment" {
    set result [::aurig::core::util::_yaml_parse_scalar {'it''s'   # owner}]
    assert_eq $result {it's}
}

test "Bare `#` at start of value → empty (Copilot PR #85 round-3)" {
    # YAML form `key: # comment` (no value, just comment) — the
    # `_yaml_parse_block` regex captures everything after the `:` as the
    # scalar, so `_yaml_parse_scalar` receives `# comment`. Without the
    # `(?:^|\s+)#` branch in the regsub, the value was returned as the
    # literal `# comment` string, contradicting the "inline comments are
    # stripped" promise.
    set result [::aurig::core::util::_yaml_parse_scalar "# comment"]
    assert_eq $result ""
}

test "Bare `#` at start with leading whitespace → empty (Copilot PR #85 round-3)" {
    set result [::aurig::core::util::_yaml_parse_scalar "   # comment"]
    assert_eq $result ""
}

# =============================================================================
# Suite 2: readYamlMinimal end-to-end — write a manifest mirroring the
# real-world Sentinel case and assert the parsed dict carries the stripped
# scalar.
# =============================================================================
puts ""
puts "Suite 2: readYamlMinimal end-to-end on Sentinel-style manifest"
puts "--------------------------------------------------------------"

set tmpdir [file join $script_dir ".tmp_yaml_minimal_032"]
file delete -force $tmpdir
file mkdir $tmpdir
set manifest [file join $tmpdir "manifest.yaml"]
set fp [open $manifest w]
fconfigure $fp -translation lf
puts $fp "project_name: SentinelSampleProject       # human-readable label"
puts $fp "project_root: ../..                       # commento inline esplicativo"
puts $fp "top: TopEnt                               # toplevel"
puts $fp "quoted_field: \"value # preserved\"       # only this hash is stripped"
close $fp

set parsed [::aurig::core::util::readYamlMinimal $manifest]

test "project_name parsed with inline comment stripped" {
    global parsed
    assert_eq [dict get $parsed project_name] "SentinelSampleProject"
}

test "project_root parsed as `../..` (NOT the literal incl. comment)" {
    global parsed
    assert_eq [dict get $parsed project_root] "../.."
}

test "top parsed with inline comment stripped" {
    global parsed
    assert_eq [dict get $parsed top] "TopEnt"
}

test "quoted_field preserves inner `#` literally; outer trailing comment stripped" {
    global parsed
    assert_eq [dict get $parsed quoted_field] "value # preserved"
}

# Cleanup
catch {file delete -force $tmpdir}

puts ""
puts "============================================================"
puts "  Tests run:    $tests_run"
puts "  Tests passed: $tests_passed"
puts "  Tests failed: $tests_failed"
puts "============================================================"

if {$tests_failed > 0} { exit 1 }
exit 0
