# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Helpers for robust ARCH splitting (comment/string aware, balanced)
#=============================================================================
namespace eval ::aurig::core::analyze {}

# Advance one character, honoring --comments, "..." (with "" escape), and '.' character literals
proc ::aurig::core::analyze::_adv {s stVar} {
    upvar 1 $stVar st
    set n [string length $s]
    if {$st(i) >= $n} { return 0 }

    set ch  [string index $s $st(i)]
    set ch2 [expr {$st(i)+1 < $n ? [string index $s [expr {$st(i)+1}]] : ""}]
    set ch3 [expr {$st(i)+2 < $n ? [string index $s [expr {$st(i)+2}]] : ""}]

    # -- comment (only if not in string or character literal)
    if {!$st(in_str) && !$st(in_char) && $ch eq "-" && $ch2 eq "-"} {
        incr st(i) 2
        while {$st(i) < $n && [string index $s $st(i)] ne "\n"} { incr st(i) }
        return 1
    }
    
    # Character literal: 'X' where X is any single character (VHDL)
    # Only process if not already in a string
    if {!$st(in_str) && $ch eq "'" && $ch3 eq "'"} {
        # This is a character literal, skip all three characters
        incr st(i) 3
        return 1
    }
    
    # String literal, with doubled "" escape
    if {$ch eq "\""} {
        if {!$st(in_str)} {
            set st(in_str) 1
            incr st(i)
        } else {
            if {$ch2 eq "\""} { incr st(i) 2 } else { incr st(i); set st(in_str) 0 }
        }
        return 1
    }

    incr st(i)
    return 1
}

# Next identifier-like word; returns {word start end} or {"" i i}
proc ::aurig::core::analyze::_nextw {s i} {
    set n [string length $s]
    while {$i < $n} {
        set ch [string index $s $i]
        if {[string is alpha $ch] || $ch eq "_"} { break }
        incr i
    }
    if {$i >= $n} { return [list "" $i $i] }
    set b $i
    incr i
    while {$i < $n} {
        set ch [string index $s $i]
        if {![string is alnum $ch] && $ch ne "_"} { break }
        incr i
    }
    return [list [string range $s $b [expr {$i-1}]] $b $i]
}

# Peek the next two identifier-words after index `idx`, but STOP at ';'
# Returns: w2 s2 e2 w3 s3 e3
# - wX  : the matched word ("" if a ';' is hit before the word)
# - sX  : start index of the word (or the semicolon index if wX == "")
# - eX  : end index (exclusive) of the word (or same as sX if wX == "")
#
# Notes:
# - A "word" here is [A-Za-z_]\w* (VHDL-like identifier)
# - We skip ASCII whitespace between tokens
# - If we hit ';' while scanning or while skipping spaces, we stop and return "" for that word
# - We do NOT advance past the ';' (so caller can see the 'begin' directly after)
proc ::aurig::core::analyze::_peek2w_stop_at_semicolon {chunk idx} {
    set N [string length $chunk]

    # local lambda-ish helper
    proc ::aurig::core::analyze::__peek1 {chunk idx N} {
        # skip spaces
        set i $idx
        while {$i < $N && [string is space -strict [string index $chunk $i]]} {incr i}
        if {$i >= $N} {
            return [list "" $N $N $N 0]  ;# w s e next_i hit_semicolon
        }
        # stop if ';' right here
        if {[string index $chunk $i] eq ";"} {
            # return empty word, position at semicolon
            return [list "" $i $i $i 1]
        }
        # try to match an identifier starting at i
        # We require the match to start exactly at i
        if {[regexp -indices -start $i {([A-Za-z_]\w*)} $chunk m]} {
            lassign $m s e
            if {$s == $i} {
                # word found
                set w [string range $chunk $s $e]
                return [list $w $s [expr {$e+1}] [expr {$e+1}] 0]
            }
        }
        # Not an identifier; return empty (no semicolon hit)
        return [list "" $i $i $i 0]
    }

    # First word
    lassign [::aurig::core::analyze::__peek1 $chunk $idx $N] w2 s2 e2 next_i hitSemi
    if {$hitSemi} {
        # Semicolon before any word: second word also empty at same position
        return [list "" $s2 $e2 "" $s2 $e2]
    }

    # Second word (start from end of first word)
    lassign [::aurig::core::analyze::__peek1 $chunk $next_i $N] w3 s3 e3 _ hitSemi2
    if {$hitSemi2} {
        # Semicolon before second word: return empty second word
        return [list $w2 $s2 $e2 "" $s3 $e3]
    }

    return [list $w2 $s2 $e2 $w3 $s3 $e3]
}


# END kinds that do NOT correspond to a prior BEGIN (do NOT change begin-depth)
proc ::aurig::core::analyze::_end_is_shallow {nextWord next2Word} {
    # Combine possible two-word forms (e.g., "package body", "protected body")
    set a [string tolower $nextWord]
    set b [string tolower $next2Word]
    if {$a eq ""} { return 0 }  ;# "end;" closes a begin
    # NOTE: "generate" removed from this list because generate blocks CAN have begin...end
    if {$a in {"if" "case" "loop" "record" "units" "component" "package" "entity" "type" "protected"}} {
        # Special-cases that are ALWAYS shallow for architecture BODY balancing.
        # (They don't correspond to a prior BEGIN in the architecture BODY.)
        return 1
    }
    # Treat "package body" and "protected body" as shallow too
    if {$a eq "package" && $b eq "body"}   { return 1 }
    if {$a eq "protected" && $b eq "body"} { return 1 }
    return 0
}

#=============================================================================
# CORE: split_arch_decl_body
# Input:  chunk that starts RIGHT AFTER 'is' of the architecture header
# Output: dict {decl body end_tail ranges{...}}
#=============================================================================
proc ::aurig::core::analyze::split_arch_decl_body {chunk} {
    # -------- Phase 1: find TRUE architecture 'begin' (skip subprog/package bodies) --------
    array set st {i 0 in_str 0 in_char 0}
    set n [string length $chunk]
    set depth 0
    set beginStart -1
    set beginEnd   -1
    set pending_subprog 0
    set seen_is_after_subprog 0

    while {$st(i) < $n} {
        lassign [::aurig::core::analyze::_nextw $chunk $st(i)] w b e
        if {$w eq ""} { ::aurig::core::analyze::_adv $chunk st; continue }
        set low [string tolower $w]


        # Detect "function|procedure|package [body] ... is" in declarative part
        if {$low in {"function" "procedure" "package"}} {
            set seen_is_after_subprog 1
            set st(i) $e
            continue
        }
        if {$seen_is_after_subprog && $low eq "is"} {
            set pending_subprog 1
            set seen_is_after_subprog 0
            set st(i) $e
            continue
        }

        if {$low eq "begin"} {
            if {$depth == 0} {
                if {$pending_subprog} {
                    # This 'begin' starts a subprogram/package body in DECL part; treat as nested.
                    incr depth
                    set pending_subprog 0
                    set st(i) $e
                    continue
                }
                # This is the TRUE architecture 'begin'
                set beginStart $b
                set beginEnd   $e
                break
            } else {
                incr depth
                set st(i) $e
                continue
            }
        } elseif {$low eq "end"} {
            # In declarative scan: decrement depth only for non-shallow ENDs
            # lassign [::aurig::core::analyze::_nextw $chunk $e] w2 s2 e2
            # lassign [::aurig::core::analyze::_nextw $chunk $e2] w3 s3 e3
            lassign [::aurig::core::analyze::_peek2w_stop_at_semicolon $chunk $e] w2 s2 e2 w3 s3 e3

            if {![::aurig::core::analyze::_end_is_shallow $w2 $w3]} {
                if {$depth > 0} { incr depth -1 }
            }
            set st(i) [expr {$w2 eq "" ? $e : ($w3 eq "" ? $e2 : $e3)}]
            continue
        }

        set st(i) $e
    }

    if {$beginStart < 0} {
        return -code error "split_arch_decl_body: could not find architecture BEGIN in chunk."
    }

    set decl [string trim [string range $chunk 0 [expr {$beginStart-1}]]]

    # -------- Phase 2: from architecture 'begin' to its matching 'end ... ;' --------
    # Goal: extract body from architecture BEGIN to its matching END.
    #
    # Generate block depth handling:
    # - 'generate' keyword increments depth by 1 (introduces a block level)
    #   and records the depth on `gen_stack` (= "this generate is still
    #   waiting for its optional 'begin'").
    # - A `begin` whose depth equals the top of `gen_stack` AND that is not
    #   the body of a pending subprogram is the generate's own begin: pop
    #   the entry and do NOT increment depth.
    # - A body-introducer (`process`/`block`) at the same depth as the top
    #   of `gen_stack` means the generate uses the "implicit body" form
    #   (no explicit `begin`); drop the stack entry so that the following
    #   `begin` of the process/block is counted normally.
    # - Subprogram bodies inside a generate's declarative region are
    #   tracked like in Phase 1: a `function|procedure` keyword followed
    #   later by `is` arms `sub_pending`, and the next `begin` then opens
    #   a subprogram body (depth++) without consuming the generate marker.
    # - 'end generate' decrements depth and pops the matching stack entry
    #   if the generate had no `begin` of its own.
    # - Other `end` constructs use `_end_is_shallow` to decide if depth
    #   decrements.

    array set st2 [list i $beginEnd in_str 0 in_char 0]
    set depth 1
    set endKwStart -1
    set endKwEnd -1
    set gen_stack [list]
    set sub_pending 0

    while {$st2(i) < $n} {
        lassign [::aurig::core::analyze::_nextw $chunk $st2(i)] w b e
        if {$w eq ""} { ::aurig::core::analyze::_adv $chunk st2; continue }
        set low [string tolower $w]

        # When a subprogram keyword (`function`|`procedure`) appears in the
        # architecture body, look ahead once to its top-level terminator and
        # classify it as a prototype or a body:
        #   - if the next top-level token is `;`, it's a prototype: skip past
        #     the `;` and continue (do NOT arm `sub_pending`).
        #   - if the next top-level token is `is`, it's a body: arm
        #     `sub_pending` so the following `begin` opens a real depth, and
        #     skip past `is` so the surrounding scanner doesn't try to
        #     re-classify it.
        # The lookahead must be paren-aware (skip `;` inside the parameter
        # list), string-aware (`"..."`), character-literal-aware (`'X'` via
        # 3-char lookahead) and comment-aware (`-- ...\n`). Performing this
        # once per subprogram keyword keeps the architecture body scan
        # linear; the previous per-iteration rescan was O(n²).
        if {$low in {"function" "procedure"}} {
            set _j $e
            set _paren 0
            set _in_dq 0
            set _outcome "eof"
            while {$_j < $n} {
                set _c [string index $chunk $_j]
                # VHDL string literal: doubled quotes ("") are a literal
                # quote and do NOT end the string; a single " ends it.
                # Backslash has no escape meaning.
                if {$_in_dq} {
                    if {$_c eq "\""} {
                        if {$_j+1 < $n && [string index $chunk [expr {$_j+1}]] eq "\""} {
                            incr _j 2
                            continue
                        }
                        set _in_dq 0
                    }
                    incr _j
                    continue
                }
                if {$_c eq "\""} { set _in_dq 1; incr _j; continue }
                if {$_c eq "'"} {
                    if {$_j+2 < $n && [string index $chunk [expr {$_j+2}]] eq "'"} {
                        incr _j 3; continue
                    }
                    incr _j; continue
                }
                if {$_c eq "-" && $_j+1 < $n && [string index $chunk [expr {$_j+1}]] eq "-"} {
                    set _nl [string first "\n" $chunk $_j]
                    if {$_nl < 0} { set _j $n; continue }
                    set _j [expr {$_nl + 1}]; continue
                }
                if {$_c eq "("} { incr _paren; incr _j; continue }
                if {$_c eq ")"} {
                    if {$_paren > 0} { incr _paren -1 }
                    incr _j; continue
                }
                if {$_paren == 0} {
                    if {$_c eq ";"} {
                        set _outcome "prototype"
                        set _j [expr {$_j + 1}]
                        break
                    }
                    # Match top-level `is` as a keyword (whole-word, case
                    # insensitive). Surrounding chars must not be identifier
                    # characters.
                    if {($_c eq "i" || $_c eq "I") && $_j+1 < $n} {
                        set _c2 [string index $chunk [expr {$_j+1}]]
                        if {$_c2 eq "s" || $_c2 eq "S"} {
                            set _before [expr {$_j > 0 ? [string index $chunk [expr {$_j-1}]] : " "}]
                            set _after_idx [expr {$_j + 2}]
                            set _after [expr {$_after_idx < $n ? [string index $chunk $_after_idx] : " "}]
                            set _before_ok [expr {![string is alnum -strict $_before] && $_before ne "_"}]
                            set _after_ok [expr {![string is alnum -strict $_after] && $_after ne "_"}]
                            if {$_before_ok && $_after_ok} {
                                set _outcome "body"
                                set _j $_after_idx
                                break
                            }
                        }
                    }
                }
                incr _j
            }

            if {$_outcome eq "body"} {
                set sub_pending 1
                set st2(i) $_j
            } elseif {$_outcome eq "prototype"} {
                set st2(i) $_j
            } else {
                set st2(i) $e
            }
            continue
        }

        if {$low eq "generate"} {
            incr depth
            lappend gen_stack $depth
            set st2(i) $e
            continue
        }

        if {$low in {"process" "block"}} {
            # Generate's implicit body: drop a pending generate marker at
            # this depth so the following 'begin' is counted as a normal
            # process/block body opener.
            if {[llength $gen_stack] > 0 && [lindex $gen_stack end] == $depth} {
                set gen_stack [lrange $gen_stack 0 end-1]
            }
            set st2(i) $e
            continue
        }

        if {$low eq "begin"} {
            if {$sub_pending} {
                # Subprogram body opener
                incr depth
                set sub_pending 0
                set st2(i) $e
                continue
            }
            if {[llength $gen_stack] > 0 && [lindex $gen_stack end] == $depth} {
                # This 'begin' closes the declarative section of the
                # generate at the top of the stack; depth is already correct.
                set gen_stack [lrange $gen_stack 0 end-1]
                set st2(i) $e
                continue
            }
            incr depth
            set st2(i) $e
            continue
        }

        if {$low eq "end"} {
            lassign [::aurig::core::analyze::_peek2w_stop_at_semicolon $chunk $e] w2 s2 e2 w3 s3 e3

            set w2_low [string tolower $w2]
            set is_end_generate [expr {$w2_low eq "generate"}]

            if {$is_end_generate} {
                if {$depth > 0} { incr depth -1 }
                if {[llength $gen_stack] > 0 && [lindex $gen_stack end] > $depth} {
                    # The generate at the top of the stack had no 'begin' of
                    # its own; drop its pending marker now that it has ended.
                    set gen_stack [lrange $gen_stack 0 end-1]
                }
            } elseif {![::aurig::core::analyze::_end_is_shallow $w2 $w3]} {
                if {$depth > 0} { incr depth -1 }
            }

            if {$depth == 0} {
                set endKwStart $b
                if {$w2 eq ""} {
                    set endKwEnd $e
                } elseif {$w3 eq ""} {
                    set endKwEnd $e2
                } else {
                    set endKwEnd $e3
                }
                break
            }

            if {$w2 eq ""} {
                set st2(i) $e
            } elseif {$w3 eq ""} {
                set st2(i) $e2
            } else {
                set st2(i) $e3
            }
            continue
        }

        set st2(i) $e
    }

    if {$endKwStart < 0} {
        return -code error "split_arch_decl_body: could not find matching END in chunk. Depth=$depth (unbalanced begin/end constructs)."
    }
    
    # Additional validation: check if depth is zero (properly balanced)
    if {$depth != 0} {
        return -code error "split_arch_decl_body: unbalanced begin/end constructs detected. Final depth=$depth (expected 0)."
    }

    set body [string trim [string range $chunk $beginStart [expr {$endKwEnd+1}]]]

    # Capture "end ... ;" (inclusive semicolon) as tail
    set tail    [string range $chunk $endKwStart end]
    set semiIdx [string first ";" $tail]
    set end_tail [expr {$semiIdx >= 0 ? [string range $tail 0 $semiIdx] : $tail}]

    return [dict create \
        decl     $decl \
        body     $body \
        end_tail $end_tail \
        ranges   [dict create decl "0-[expr {$beginStart-1}]" body "$beginStart-[expr {$endKwStart-1}]"]]
}


# -------------------------------
# Dict helper: push into last architecture's sublist
# -------------------------------
proc ::aurig::core::analyze::_push_into_last_arch {D key item} {
    if {![dict exists $D architectures]} {
        error "parse_architecture_body: no architectures list present in dict"
    }
    set archs [dict get $D architectures]
    if {[llength $archs] == 0} {
        error "parse_architecture_body: empty architectures list"
    }
    set lastIdx [expr {[llength $archs]-1}]
    set A [lindex $archs $lastIdx]
    if {![dict exists $A $key]} {
        dict set A $key {}
    }
    set lst [dict get $A $key]
    lappend lst $item
    dict set A $key $lst
    set archs [lreplace $archs $lastIdx $lastIdx $A]
    dict set D architectures $archs
    return $D
}

# -------------------------------
# Whitespace normalizer (preserve newlines)
# - we DO NOT remove lines (to keep line numbers stable)
# -------------------------------
proc ::aurig::core::analyze::_normalize_ws_keep_lines {s} {
    set out {}
    foreach line [split $s \n] {
        # tabs -> single spaces, collapse multi-spaces (only within the line)
        set line [regsub -all {\t} $line { }]
        set line [regsub -all {  +} $line { }]
        append out [string trimright $line] \n
    }
    return $out
}

# -------------------------------
# Index -> absolute line number
# n is the absolute line of archBody's first line
# -------------------------------
proc ::aurig::core::analyze::_index_to_line {text idx n} {
    # Count newlines before the given index in the text
    # n is the base line number (1-based) for the start of text
    set prefix [string range $text 0 [expr {$idx-1}]]
    set newlines [regexp -all \n $prefix]
    return [expr {$n + $newlines}]
}

# Split by top-level commas, ignoring commas inside (), [], '...', "..."
# - txt: the text to split, e.g. "GEN1 => 3, GEN2 => f(a,b), GEN3 => \"x,y\""
# Returns a list of trimmed parts.
proc ::aurig::core::analyze::_split_top_level_commas {txt} {
    set parts {}
    set start 0
    set level 0              ;# parentheses/brackets depth
    set in_dquote 0          ;# inside double quotes "..."
    set N [string length $txt]

    for {set i 0} {$i < $N} {incr i} {
        set ch [string index $txt $i]

        # VHDL string literal: doubled quotes ("") are a literal quote and
        # do NOT end the string; a single " ends it. Backslash has no
        # escape meaning (it is just an ordinary character).
        if {$in_dquote} {
            if {$ch eq "\""} {
                if {$i+1 < $N && [string index $txt [expr {$i+1}]] eq "\""} {
                    incr i
                } else {
                    set in_dquote 0
                }
            }
            continue
        }

        # Single-quote disambiguation (same rule as `_grab_paren_block`):
        #   character literal 'X'     : exactly 3 chars, third must be '
        #   attribute selector x'attr : lone ', treat as ordinary character
        # Without this, a port-map actual like `din_i(din_i'left)` opens a
        # pseudo single-quoted region that swallows the next comma, merging
        # the following association into the same actual.
        if {$ch eq "'"} {
            if {$i+2 < $N && [string index $txt [expr {$i+2}]] eq "'"} {
                incr i 2
                continue
            }
            continue
        }

        # Not in quotes: handle structure and commas safely
        switch -exact -- $ch {
            "\"" { set in_dquote 1 }

            "(" - "[" {
                incr level
            }
            ")" - "]" {
                if {$level > 0} { incr level -1 }
            }

            "," {
                if {$level == 0} {
                    # cut part from 'start' up to char before comma
                    set seg [string range $txt $start [expr {$i-1}]]
                    lappend parts [string trim $seg]
                    set start [expr {$i+1}]
                }
            }

            default {
                # nothing
            }
        }
    }

    # trailing segment
    set last [string trim [string range $txt $start end]]
    if {$last ne ""} {
        lappend parts $last
    } elseif {[llength $parts] == 0} {
        # empty input -> return empty list
    }
    return $parts
}

# Parse "A=>1" or positional "foo(x)" item -> {name value}, name=="" if positional
proc ::aurig::core::analyze::_parse_assoc {s} {
    if {[regexp -indices -nocase {^(.*?)=>\s*(.*)$} $s -> aIdx bIdx]} {
        set name  [string trim [string range $s {*}$aIdx]]
        set value [string trim [string range $s [expr {[lindex $bIdx 0]}] end]]
        return [list $name $value]
    }
    return [list "" [string trim $s]]
}

# Build a normalized dict for association lists:
# Returns dict with keys:
#   named       -> dict of name->value   (always present, maybe empty)
#   positional  -> list of values        (always present, maybe empty)
#   order       -> list preserving order: each item is {name value} (name "" if positional)
#   has_named   -> 0/1
#   has_positional -> 0/1
# Also enforces VHDL rule: once named used, no more positional.
proc ::aurig::core::analyze::_assoc_parts {txt} {
    set named {}
    set positional {}
    set order {}
    set seen_named 0
    foreach item [::aurig::core::analyze::_split_top_level_commas $txt] {
        if {$item eq ""} continue
        lassign [::aurig::core::analyze::_parse_assoc $item] k v
        if {$k eq ""} {
            if {$seen_named} {
                # VHDL disallows positional after named
                # You can choose to error, warn, or just record it.
                # Here: record, and you may also 'puts' a warning.
                puts "WARN: positional association after named is not allowed in VHDL: \"$item\""
            }
            lappend positional $v
        } else {
            set seen_named 1
            dict set named $k $v
        }
        lappend order [list $k $v]
    }
    set res {}
    dict set res named $named
    dict set res positional $positional
    dict set res order $order
    dict set res has_named [expr {[dict size $named] > 0}]
    dict set res has_positional [expr {[llength $positional] > 0}]
    return $res
}

# Full assoc list: "A=>1, B=>f(x,y), C=>\"x,y\""
proc ::aurig::core::analyze::_parse_assoc_list {txt} {
    set res {}
    foreach item [::aurig::core::analyze::_split_top_level_commas $txt] {
        if {$item eq ""} continue
        lassign [::aurig::core::analyze::_parse_assoc $item] k v
        lappend res [list $k $v]
    }
    return $res
}

# Safe dict-get with default
proc ::aurig::core::analyze::_dictget {D key {default {}}} {
    if {[dict exists $D $key]} { return [dict get $D $key] }
    return $default
}

# Grab a balanced (...) starting exactly at index 'lparenI' where chunk[lparenI] == "("
# Returns dict: content (inside text), start, end, next (index right after ')')
proc ::aurig::core::analyze::_grab_paren_block {chunk lparenI} {
    set N [string length $chunk]
    if {$lparenI >= $N || [string index $chunk $lparenI] ne "("} {
        error "_grab_paren_block: start index $lparenI is not '('"
    }
    set i [expr {$lparenI+1}]
    set level 1
    set in_dq 0
    while {$i < $N} {
        set ch [string index $chunk $i]

        # VHDL string literal: doubled quotes ("") are a literal quote and
        # do NOT end the string; a single " ends it. Backslash has no
        # escape meaning (it is just an ordinary character).
        if {$in_dq} {
            if {$ch eq "\""} {
                if {$i+1 < $N && [string index $chunk [expr {$i+1}]] eq "\""} {
                    incr i 2
                    continue
                }
                set in_dq 0
            }
            incr i
            continue
        }

        # line comments
        if {$ch eq "-" && $i+1 < $N && [string index $chunk [expr {$i+1}]] eq "-"} {
            set nl [string first "\n" $chunk $i]
            if {$nl < 0} { set i $N; break }
            set i [expr {$nl+1}]
            continue
        }

        # Single-quote disambiguation:
        #   - character literal 'X'  : exactly 3 chars, the third must be '
        #   - attribute selector name'attr (e.g. signal'left, signal'range) :
        #     a lone ' immediately after an identifier character; never paired
        # The matching-paren logic must not treat the attribute selector as
        # opening a quoted region, otherwise a port map like
        # `din_i(0) => fix_in_i(fix_in_i'left)` is misread as entering a
        # never-closing string and the surrounding ')' is lost.
        if {$ch eq "'"} {
            if {$i+2 < $N && [string index $chunk [expr {$i+2}]] eq "'"} {
                incr i 3
                continue
            }
            incr i
            continue
        }

        switch -exact -- $ch {
            "\"" { set in_dq 1; incr i; continue }
            "("  { incr level; incr i; continue }
            ")"  {
                incr level -1
                if {$level == 0} {
                    set start $lparenI
                    set end   $i
                    set next  [expr {$i+1}]
                    set content [string range $chunk [expr {$start+1}] [expr {$end-1}]]
                    return [dict create content $content start $start end $end next $next]
                }
                incr i; continue
            }
            default { incr i }
        }
    }
    error "_grab_paren_block: no matching ')' found"
}

# Find the matching 'end' for a process statement.
# Accepts: "end;", "end process;", "end process <label>;", "end <label>;"
# Rejects: "end if;", "end case;", "end loop;", etc.
# Returns dict: {found 0/1 eStart eEnd semiIdx}
proc ::aurig::core::analyze::_find_end_of_process {text startIdx label} {
    set N [string length $text]
    set i $startIdx
    while {$i < $N} {
        # next word
        lassign [::aurig::core::analyze::_nextw $text $i] w s e
        if {$w eq ""} { break }
        if {[string tolower $w] ne "end"} {
            set i $e
            continue
        }

        # Peek words up to the first ';' without crossing it
        lassign [::aurig::core::analyze::_peek2w_stop_at_semicolon $text $e] w2 s2 e2 w3 s3 e3
        set lw2 [string tolower $w2]
        set lw3 [string tolower $w3]
        set llabel [string tolower $label]

        # Decide if this 'end' closes the process
        set is_ours 0
        if {$w2 eq ""} {
            # plain "end;" -> treat as ours
            set is_ours 1
        } elseif {$lw2 eq "process"} {
            # "end process [label];" -> ours
            set is_ours 1
            # optional label match is fine; don't require it
        } elseif {$llabel ne "" && $lw2 eq $llabel} {
            # "end <label>;" -> ours
            set is_ours 1
        } else {
            # Not ours if it names another construct we don't close
            # (if/case/loop/record/package/protected/block/function/procedure/architecture/component/generate)
            # Otherwise skip
        }

        if {$is_ours} {
            # Find the following ';'
            set semi -1
            for {set j $e} {$j < $N} {incr j} {
                if {[string index $text $j] eq ";"} { set semi $j; break }
            }
            if {$semi >= 0} {
                return [dict create found 1 eStart $s eEnd $e semiIdx $semi]
            } else {
                return [dict create found 0]
            }
        }

        # Not ours → continue scanning after what we peeked (but before ';')
        set i [expr {$w2 eq "" ? $e : ($w3 eq "" ? $e2 : $e3)}]
    }
    return [dict create found 0]
}


# Find the BEGIN that ends a declarative part (depth 0),
# skipping BEGINs inside nested subprograms/packages/etc.
# - chunk    : text slice of the whole construct (from its header up to its 'end ...;')
# - startIdx : where to start scanning (right after the header "... is" or "process (...) [is]")
# - endIdx   : where to stop (start of "end <kw>" for this construct); use [string length $chunk] if unknown
#
# Requires your existing token helpers:
#   ::aurig::core::analyze::_nextw
#   ::aurig::core::analyze::_peek2w_stop_at_semicolon
#
# Depth +1 when we enter a nested declarative/compound that has its own 'begin'/'end':
#   function, procedure (also 'pure|impure function')
#   package, protected  (no 'begin' inside, but they use 'end <kw>;' → still treated as nested)
# For architecture/process/block/subprogram declaratives this is sufficient.
proc ::aurig::core::analyze::_find_decl_body_begin {chunk startIdx endIdx} {
    set i $startIdx
    set N [string length $chunk]
    if {$endIdx < 0 || $endIdx > $N} { set endIdx $N }

    set depth 0
    while {$i < $endIdx} {
        lassign [::aurig::core::analyze::_nextw $chunk $i] w s e
        if {$w eq ""} { break }
        set lw [string tolower $w]

        # Handle 'pure|impure function' as 'function'
        if {$lw in {pure impure}} {
            lassign [::aurig::core::analyze::_nextw $chunk $e] w2 s2 e2
            if {[string tolower $w2] eq "function"} {
                incr depth
                set i $e2
                continue
            }
            set i $e
            continue
        }

        switch -- $lw {
            function - procedure - package - protected {
                # Enter nested declaration scope
                incr depth
                set i $e
                continue
            }
            end {
                # Classify END without skipping past ';'
                lassign [::aurig::core::analyze::_peek2w_stop_at_semicolon $chunk $e] w2 s2 e2 w3 s3 e3
                set kw [string tolower $w2]
                if {$kw in {function procedure package protected}} {
                    if {$depth > 0} { incr depth -1 }
                } elseif {$w2 eq ""} {
                    # 'end;' with no keyword — conservatively pop if we’re inside something
                    if {$depth > 0} { incr depth -1 }
                }
                # Advance up to where we peeked; do NOT eat the semicolon
                set i [expr {$w2 eq "" ? $e : ($w3 eq "" ? $e2 : $e3)}]
                continue
            }
            begin {
                if {$depth == 0} { return $s }
                # otherwise it's a nested 'begin' (inside a subprogram body), ignore
                set i $e
                continue
            }
            default {
                set i $e
            }
        }
    }
    return -1
}

# Return index just AFTER:  "process [ ( … ) ] [ is ]"
# chunk: the statement slice from label..';'
# startIdx: where the word 'process' starts inside chunk
proc ::aurig::core::analyze::_process_header_end {chunk startIdx} {
    set N [string length $chunk]
    # find the word 'process' at startIdx
    if {![regexp -indices -nocase -start $startIdx {\bprocess\b} $chunk m]} {
        return $startIdx
    }
    lassign $m s e
    set i [expr {$e+1}]
    # skip whitespace
    while {$i < $N && [string is space -strict [string index $chunk $i]]} { incr i }
    # optional sensitivity list
    if {$i < $N && [string index $chunk $i] eq "("} {
        set blk [::aurig::core::analyze::_grab_paren_block $chunk $i]
        set i   [dict get $blk next]
        while {$i < $N && [string is space -strict [string index $chunk $i]]} { incr i }
    }
    # optional 'is'
    if {$i < $N && [regexp -nocase -indices -start $i {^is\b} $chunk _]} {
        set i [expr {$i + 2}]
        while {$i < $N && [string is space -strict [string index $chunk $i]]} { incr i }
    }
    return $i
}

# --------------------------------
# Scan instantiations (entity or component forms)
# --------------------------------
proc ::aurig::core::analyze::_scan_instantiations {body n {commentDict {}}} {
    set results {}
    set idx 0
    set N [string length $body]
    while {$idx < $N} {
        if {![regexp -indices -start $idx {(\w+)\s*:\s*(?=entity|\w+)} $body mIdx]} {
            break
        }
        lassign $mIdx mStart mEnd
        
        # Quick check: is this a generate statement?
        # Look ahead to see if we have "if/for ... generate" before any semicolon
        set checkStr [string range $body $mStart [expr {min($mStart + 200, $N-1)}]]
        set checkFlat [string map {"\n" " " "\r" " "} $checkStr]
        if {[regexp -nocase {^(\w+)\s*:\s*(if|for)\s+.*?\sgenerate(\s|$)} $checkFlat]} {
            # This is a generate statement - find its body and scan recursively
            if {[regexp -indices -nocase -start $mStart -- $::aurig::core::util::re::re_generate_kw $body genIdx]} {
                set genStart [expr {[lindex $genIdx 1] + 1}]
                
                # Find matching "end generate" by tracking depth
                set depth 1
                set genEnd -1
                set i $genStart
                while {$i < $N && $depth > 0} {
                    if {[regexp -indices -nocase -start $i -- $::aurig::core::util::re::re_generate_kw $body gIdx]} {
                        set gPos [lindex $gIdx 0]
                        if {[regexp -indices -nocase -start $i -- $::aurig::core::util::re::re_end_generate_kw $body egIdx]} {
                            set egPos [lindex $egIdx 0]
                            if {$egPos < $gPos || $gPos == -1} {
                                # Found "end generate" before next "generate"
                                incr depth -1
                                if {$depth == 0} {
                                    set genEnd $egPos
                                    break
                                }
                                set i [expr {[lindex $egIdx 1] + 1}]
                            } else {
                                # Found nested "generate"
                                incr depth
                                set i [expr {[lindex $gIdx 1] + 1}]
                            }
                        } else {
                            # Found "generate" with no more "end generate"
                            incr depth
                            set i [expr {[lindex $gIdx 1] + 1}]
                        }
                    } elseif {[regexp -indices -nocase -start $i -- $::aurig::core::util::re::re_end_generate_kw $body egIdx]} {
                        # Found "end generate"
                        incr depth -1
                        if {$depth == 0} {
                            set genEnd [lindex $egIdx 0]
                            break
                        }
                        set i [expr {[lindex $egIdx 1] + 1}]
                    } else {
                        incr i
                    }
                }
                
                if {$genEnd > $genStart} {
                    # Extract generate body and recursively scan it
                    set genBody [string range $body $genStart [expr {$genEnd - 1}]]
                    set genLineOffset [::aurig::core::analyze::_index_to_line $body $genStart $n]
                    set genInsts [::aurig::core::analyze::_scan_instantiations $genBody $genLineOffset $commentDict]
                    foreach inst $genInsts {
                        lappend results $inst
                    }
                }
                
                # Skip past "end generate"
                if {$genEnd >= 0} {
                    if {[regexp -indices -nocase -start $genEnd -- $::aurig::core::util::re::re_end_generate_kw $body egIdx]} {
                        set idx [expr {[lindex $egIdx 1] + 1}]
                    } else {
                        set idx [expr {$genEnd + 1}]
                    }
                } else {
                    set idx [expr {$genStart + 1}]
                }
                continue
            }
        }
        
        # find statement ';' with basic paren tracking
        set level 0
        set semi -1
        for {set i $mStart} {$i < $N} {incr i} {
            set ch [string index $body $i]
            if {$ch eq "("} {incr level}
            if {$ch eq ")"} {incr level -1}
            if {$ch eq ";" && $level == 0} { set semi $i; break }
        }
        if {$semi < 0} { set idx [expr {$mEnd+1}]; continue }

        set chunk [string range $body $mStart $semi]
        if {![regexp {^\s*(\w+)\s*:\s*(.+)$} $chunk -> label right]} {
            set idx [expr {$semi+1}]
            continue
        }

        set form ""; set lib ""; set comp ""; set arch ""; set tail ""

        # Guard: block headers are NOT instantiations
        if {[regexp -nocase {^block(\s|$)} [string map {"\n" " "} $right]]} {
            set idx [expr {$semi+1}]
            continue
        }

        # entity form:  entity lib.entity (arch)
        if {[regexp {^entity\s+([A-Za-z_]\w*)\.([A-Za-z_]\w*)(?:\s*\(\s*([A-Za-z_]\w*)\s*\))?} $right -> lib comp arch]} {
            set form "entity"
            set tail [regsub {^entity\s+[A-Za-z_]\w*\.[A-Za-z_]\w*(?:\s*\(\s*[A-Za-z_]\w*\s*\))?} $right {}]

        # explicit component form:  component <name>
        } elseif {[regexp {^component\s+([A-Za-z_]\w*)} $right -> comp]} {
            set form "component"
            set tail [regsub {^component\s+[A-Za-z_]\w*} $right {}]

        # shorthand component form:  <name>  (must be followed somewhere by 'port map (')
        } elseif {[regexp {^([A-Za-z_]\w*)\s*(.*)$} $right -> comp tail]} {
            # Confirm it's an instantiation by requiring 'port map(' before the statement ';'
            set isInst [regexp -nocase -- $::aurig::core::util::re::re_port_map $chunk]
            if {!$isInst} {
                set idx [expr {$semi+1}]
                continue
            }
            set form "component"

        } else {
            set idx [expr {$semi+1}]
            continue
        }

        set tail [string trim $tail]


        set genTxt ""; set portTxt ""

        # GENERIC MAP (...)
        if {[regexp -indices -nocase -- $::aurig::core::util::re::re_generic_map $tail mG]} {
            set lparenG [lindex $mG 1]
            set gblk [::aurig::core::analyze::_grab_paren_block $tail $lparenG]
            set genTxt [dict get $gblk content]
        }

        # PORT MAP (...)
        if {[regexp -indices -nocase -- $::aurig::core::util::re::re_port_map $tail mP]} {
            set lparenP [lindex $mP 1]
            set pblk [::aurig::core::analyze::_grab_paren_block $tail $lparenP]
            set portTxt [dict get $pblk content]
        }


        # ---- get normalized association parts (dict with named/positional) ----
        set G [::aurig::core::analyze::_assoc_parts $genTxt]
        set namedG      [::aurig::core::analyze::_dictget $G named {}]       ;# dict: name -> value
        set positionalG [::aurig::core::analyze::_dictget $G positional {}]  ;# list: values

        set P [::aurig::core::analyze::_assoc_parts $portTxt]
        set namedP      [::aurig::core::analyze::_dictget $P named {}]
        set positionalP [::aurig::core::analyze::_dictget $P positional {}]

        # ---- build generics_map (positional keep order; named keep pairs) ----
        set generics_map {}
        set pos 1
        foreach v $positionalG {
            lappend generics_map [dict create pos $pos value $v]
            incr pos
        }
        dict for {k v} $namedG {
            lappend generics_map [dict create name $k value $v]
        }

        # ---- build ports_map (positional => actual; named => formal/actual) ----
        set ports_map {}
        set pos 1
        foreach v $positionalP {
            lappend ports_map [dict create pos $pos actual $v]
            incr pos
        }
        dict for {formal actual} $namedP {
            lappend ports_map [dict create formal $formal actual $actual]
        }

        # ---- finalize item ----
        set line [::aurig::core::analyze::_index_to_line $body $mStart $n]
        
        # Look up comment from previous lines if commentDict provided
        set instComment ""
        if {[dict size $commentDict] > 0} {
            set foundComment 0
            for {set i 2} {$i <= 3} {incr i} {
                set check_line [expr {$line - $i}]
                if {[dict exists $commentDict $check_line]} {
                    set cmt [dict get $commentDict $check_line comment]
                    # Skip separator lines
                    if {[regexp {^[-=*#]{5,}} $cmt]} {
                        continue
                    }
                    if {[string length [string trim $cmt]] > 5 || [regexp {^[*@]} $cmt]} {
                        # Remove leading * if present
                        regexp {^\*?\s*(.*)$} $cmt -> cmt
                        if {$instComment ne ""} {
                            set instComment "$cmt $instComment"
                        } else {
                            set instComment [string trim $cmt]
                        }
                        set foundComment 1
                    } else {
                        # Short comment, stop if we already have one
                        if {$instComment ne ""} {
                            break
                        }
                    }
                } else {
                    # No comment at this line
                    # If we already found comments, stop here (don't jump over gaps)
                    if {$foundComment} {
                        break
                    }
                    # Otherwise continue (skipping empty lines before comments)
                }
            }
        }
        
        set item [dict create \
            label        $label \
            entity       [expr {$form eq "entity" ? "${lib}.${comp}" : ""}] \
            component    [expr {$form eq "component" ? $comp : ""}] \
            architecture $arch \
            generics_map $generics_map \
            ports_map    $ports_map \
            line         $line \
        ]
        if {$instComment ne ""} {
            dict set item comment $instComment
        }

        lappend results $item
        set idx [expr {$semi+1}]
    }
    return $results
}

# --------------------------------
# Scan processes (labelled or not)
# archBody contains only BODY text; each process still has its own begin/end process;
# --------------------------------
proc ::aurig::core::analyze::_scan_processes {body n {commentDict {}}} {
    set results {}
    set N [string length $body]
    set idx 0
    while {$idx < $N} {
        if {![regexp -indices -nocase -start $idx {(?:(\m\w+\M)\s*:\s*)?process(?!\w)} $body mIdx]} {
            break
        }
        lassign $mIdx mStart mEnd
        # guard: if previous non-space token is "end", this is "end process" -> skip
        set prefix [string range $body 0 [expr {$mStart-1}]]
        # grab the last word before the match start
        set prevWord ""
        if {[regexp -nocase {\m(\w+)\M\s*$} $prefix -> prevWord]} {
            if {[string equal -nocase $prevWord "end"]} {
                # skip this occurrence; continue scanning after this 'process'
                set idx [expr {$mEnd+1}]
                continue
            }
        }
        #
        set label ""
        set prefix [string range $body $mStart $mEnd]
        regexp {^(\w+)\s*:} $prefix -> label

        # We already have: mStart / mEnd (end of 'process' keyword), and optional 'label'
        # Start searching AFTER the process header
        set searchFrom [expr {$mEnd}]  ;# end of 'process' word is a safe lower bound
        set hit [::aurig::core::analyze::_find_end_of_process $body $searchFrom $label]
        if {![dict get $hit found]} {
            # couldn't match this process; advance safely and continue
            set idx [expr {$mEnd+1}]
            continue
        }
        set eStart [dict get $hit eStart]
        set eEnd   [dict get $hit eEnd]
        set semi   [dict get $hit semiIdx]


        # Slice the whole statement for further parsing
        set chunk [string range $body $mStart $semi]

        # sensitivity (only if immediately after 'process')
        set sensitivity {}
        set after [string range $body [expr {$mEnd+1}] [expr {$semi-1}]]
        if {[regexp {\A\s*?\((.*)\)} $after -> inner]} {
            # Check for VHDL-2008 'all' keyword
            set innerTrimmed [string trim $inner]
            if {[string tolower $innerTrimmed] eq "all"} {
                # Special marker for 'all' sensitivity
                set sensitivity {all}
            } else {
                # Parse comma-separated signal list
                set tmp {}
                foreach s [split [string map [list \n " "] $innerTrimmed] ,] {
                    set s [string trim $s]
                    if {$s ne ""} { lappend tmp $s }
                }
                set sensitivity $tmp
            }
        }

        set classification unknown
        if {[regexp -nocase {(rising_edge|falling_edge)\s*\(} $chunk]} {
            set classification clocked
        } elseif {[llength $sensitivity] > 0} {
            # Has sensitivity list (either 'all' or explicit signals)
            set classification combinational
        }

        # Find 'begin' at depth 0 between header and 'end process'
        # Compute indices relative to 'chunk'
        set eStartRel [expr {$eStart - $mStart}]
        # Best-effort header end guess: search from after the word 'process'
        set hdrIdx [regexp -indices -nocase {process} $chunk _] ;# _ is {s e}
        
        # Find 'process' as a real word using your tokenizer
        set ps -1
        set pe -1
        set i 0
        set L [string length $chunk]
        while {$i < $L} {
            lassign [::aurig::core::analyze::_nextw $chunk $i] w s e
            if {$w eq ""} { break }
            if {[string tolower $w] eq "process"} {
                set ps $s
                set pe $e
                break
            }
            set i $e
        }
        if {$ps < 0} {
            set idx [expr {$semi+1}]
            continue
        }

        # Now compute header end reliably
        set afterHeaderIdx [::aurig::core::analyze::_process_header_end $chunk $ps]

        set bodyTxt ""
        set bS [::aurig::core::analyze::_find_decl_body_begin $chunk $afterHeaderIdx $eStartRel]
        if {$bS >= 0} {
            set bE [expr {$bS + [string length "begin"] - 1}]
            set bodyTxt [string trim [string range $chunk [expr {$bE+1}] [expr {$eStartRel - 1}]]]
        }

        set line [::aurig::core::analyze::_index_to_line $body $mStart $n]
        
        # Look up comment from previous lines if commentDict provided
        set processComment ""
        if {[dict size $commentDict] > 0} {
            set foundComment 0
            for {set i 2} {$i <= 3} {incr i} {
                set check_line [expr {$line - $i}]
                if {[dict exists $commentDict $check_line]} {
                    set cmt [dict get $commentDict $check_line comment]
                    # Skip separator lines
                    if {[regexp {^[-=*#]{5,}} $cmt]} {
                        continue
                    }
                    if {[string length [string trim $cmt]] > 5 || [regexp {^[*@]} $cmt]} {
                        # Remove leading * if present
                        regexp {^\*?\s*(.*)$} $cmt -> cmt
                        if {$processComment ne ""} {
                            set processComment "$cmt $processComment"
                        } else {
                            set processComment [string trim $cmt]
                        }
                        set foundComment 1
                    } else {
                        # Short comment, stop if we already have one
                        if {$processComment ne ""} {
                            break
                        }
                    }
                } else {
                    # No comment at this line
                    # If we already found comments, stop here (don't jump over gaps)
                    if {$foundComment} {
                        break
                    }
                    # Otherwise continue (skipping empty lines before comments)
                }
            }
        }
        
        set item [dict create \
            label          $label \
            sensitivity    $sensitivity \
            body           $bodyTxt \
            classification $classification \
            line           $line \
        ]
        if {$processComment ne ""} {
            dict set item comment $processComment
        }

        # Surface variable / constant declarations inside the process
        # declarative part (between the header and 'begin') so naming
        # rules can target them (LINT-PARSER-DEBT-021). The arch-level
        # helpers _scan_architecture_variables /
        # _scan_architecture_constants are stateless and reusable on
        # any text + base-line — they both mask nested subprograms
        # internally, so a function/procedure declared inside the
        # process declarative region is skipped naturally and its
        # own body is left to the subprogram scanners.
        if {$bS >= 0 && $bS > $afterHeaderIdx} {
            set decl_abs_start [expr {$mStart + $afterHeaderIdx}]
            set decl_raw [string range $chunk $afterHeaderIdx [expr {$bS - 1}]]
            set decl_base_line [::aurig::core::analyze::_index_to_line $body $decl_abs_start $n]
            set decls {}
            foreach v [::aurig::core::analyze::_scan_architecture_variables $decl_raw $decl_base_line] {
                lappend decls [dict create \
                    kind variable \
                    name [dict get $v name] \
                    type [dict get $v type] \
                    init [dict get $v init] \
                    line [dict get $v line]]
            }
            foreach c [::aurig::core::analyze::_scan_architecture_constants $decl_raw $decl_base_line] {
                lappend decls [dict create \
                    kind constant \
                    name [dict get $c name] \
                    type [dict get $c type] \
                    init [dict get $c init] \
                    line [dict get $c line]]
            }
            if {[llength $decls]} {
                dict set item declarations $decls
            }
        }

        lappend results $item
        set idx [expr {$semi+1}]
    }
    return $results
}

# ---------------------------------
# Scan signal declarations in an architecture declarative part
# Strategy:
#   - Regex: capture "names chunk" (everything before ':'), and "tail" (type [+ optional init]) up to first ';'
#   - Split names by comma and emit one entry per signal
#   - Extract init with the first ':=' token (not per-char split)
# ---------------------------------
proc ::aurig::core::analyze::_scan_architecture_signals {decl n {commentDict {}}} {
    set results {}
    set masked [::aurig::core::analyze::_mask_subprograms $decl]
    set N   [string length $masked]
    set idx 0

    while {$idx < $N} {
        if {![regexp -indices -start $idx -nocase {\msignal\s+} $masked matchIdx]} {
            break
        }
        lassign $matchIdx mStart mEnd
        set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $mStart]
        if {$semi < 0} {
            set idx [expr {$mEnd + 1}]
            continue
        }

        set stmt [string range $decl $mStart [expr {$semi - 1}]]
        if {![regexp -indices -nocase {^signal\s+(.+?)\s*:\s*(.*)$} $stmt -> namesRelIdx tailRelIdx]} {
            set idx [expr {$semi + 1}]
            continue
        }
        lassign $namesRelIdx nRelStart nRelEnd
        lassign $tailRelIdx  tRelStart tRelEnd
        set namesChunk [string range $stmt $nRelStart $nRelEnd]
        set tailChunk  [string range $stmt $tRelStart $tRelEnd]

        # Line points at the first character of the name list, matching the
        # legacy regex-based parser (which captured starting after the keyword).
        set line [::aurig::core::analyze::_index_to_line $decl [expr {$mStart + $nRelStart}] $n]

        # Split names by comma
        set nameList {}
        foreach raw [split $namesChunk ,] {
            set nm [string trim $raw]
            if {$nm ne {}} {
                lappend nameList $nm
            }
        }

        # Extract type and optional init using the *first* ':=' token
        set tail [string trim $tailChunk]
        set div  [string first ":=" $tail]
        if {$div < 0} {
            set signalType [string trim $tail]
            set signalInit {}
        } else {
            set signalType [string trim [string range $tail 0 [expr {$div-1}]]]
            set signalInit [string trim [string range $tail [expr {$div+2}] end]]
        }
        
        # Extract same-line or nearby comments without widening the declaration regex.
        set signalComment ""
        set lineEnd [string first "\n" $decl $semi]
        if {$lineEnd < 0} {
            set lineEnd [expr {[string length $decl] - 1}]
        } else {
            incr lineEnd -1
        }
        set commentChunk [string trim [string range $decl [expr {$semi + 1}] $lineEnd]]
        if {[regexp {^--\*?\s*(.+)$} $commentChunk -> cmt]} {
            set signalComment [string trim $cmt]
        } elseif {[llength $commentDict] > 0} {
            # Try to find comment on line immediately before signal declaration
            # Parser line numbers are off by +1, so the comment before a signal at parser-line N
            # is actually at line N-2 in the commentDict
            # Only check immediate preceding line to ensure one comment = one signal
            set commentLine [expr {$line - 2}]
            if {[dict exists $commentDict $commentLine]} {
                set commentEntry [dict get $commentDict $commentLine]
                # Extract the comment text from nested dict
                if {[dict exists $commentEntry comment]} {
                    set rawComment [dict get $commentEntry comment]
                } else {
                    set rawComment $commentEntry
                }
                # Skip separator lines
                if {![regexp {^[-=*#]{5,}} $rawComment]} {
                    # Check for descriptive comments
                    if {[string length [string trim $rawComment]] > 5 || [regexp {^[*@]} $rawComment]} {
                        set signalComment $rawComment
                    }
                }
            }
        }

        # Emit one dict per signal name
        foreach signalName $nameList {
            set item [dict create \
                name $signalName \
                type $signalType \
                init $signalInit \
                line $line \
            ]
            if {$signalComment ne ""} {
                dict set item comment $signalComment
            }
            lappend results $item
        }

        set idx [expr {$semi + 1}]
    }

    return $results
}

# ---------------------------------
# Find all function/procedure regions in a declarative part
# ---------------------------------
proc ::aurig::core::analyze::_find_subprogram_regions {decl} {
    set regions {}
    # (?i) = case-insensitive
    # captures "function ... end function" or "procedure ... end procedure"
    set re {(?is)\m(function|procedure)\M.*?\mbegin\M.*?\mend\M(?:\s+\1)?\s*;}
    set start 0
    while {[regexp -indices -start $start $re $decl matchIdx kind]} {
        lassign $matchIdx s e
        lappend regions [list $s $e]
        set start [expr {$e + 1}]
    }
    return $regions
}

# Find the semicolon that terminates a VHDL declaration statement.
# The scan is linear and avoids regex backtracking on large initializers.
proc ::aurig::core::analyze::_find_vhdl_statement_semicolon {text start} {
    set level 0
    set in_dquote 0
    set N [string length $text]
    for {set i $start} {$i < $N} {incr i} {
        set ch [string index $text $i]
        if {$in_dquote} {
            if {$ch eq "\""} { set in_dquote 0 }
            continue
        }
        if {$ch eq "\""} {
            set in_dquote 1
        } elseif {$ch eq "'"} {
            if {$i + 2 < $N && [string index $text [expr {$i + 2}]] eq "'"} {
                incr i 2
            }
        } elseif {$ch eq "("} {
            incr level
        } elseif {$ch eq ")"} {
            if {$level > 0} { incr level -1 }
        } elseif {$ch eq ";" && $level == 0} {
            return $i
        }
    }
    return -1
}

# ---------------------------------
# Mask out subprograms (function/procedure ...) by replacing their content
# with spaces (same length, same indices). Two passes:
#   1. Subprograms WITH a body: function|procedure ... begin ... end ;
#   2. Subprogram PROTOTYPES (declarations only, no body), e.g.
#        procedure poke(signal s : in std_logic);
#        function compute(value : integer) return integer;
#      Pass 1 has already erased bodies, so any remaining
#      function/procedure keyword starts a prototype that terminates at
#      the next top-level ';'. _find_vhdl_statement_semicolon correctly
#      ignores ';' inside the parameter list parens and inside strings.
# ---------------------------------
# Find the index of the ';' that terminates a subprogram definition
# starting at `kwStart` (which must be the start of a `function` or
# `procedure` keyword). Returns -1 if no closing `;` is found.
#
# Token-based walker — avoids the Tcl ARE `.*?` over-match trap
# (caught by Codex on PR #56 during LINT-PARSER-DEBT-021). The
# previous all-regex pattern was leftmost-longest and would happily
# stretch from the first subprogram's `function` keyword across
# unrelated intermediate declarations to a later subprogram's
# `end function NAME;`, swallowing real arch-level symbols in
# between.
#
# Body-construct ends (`end if;`, `end loop;`, `end case;`, etc.)
# are skipped so the walker only stops at the subprogram-closing
# end. Nested subprograms inside the declarative part of an outer
# subprogram are handled by reusing `_find_decl_body_begin` to
# locate the matching `begin`. VHDL forbids nested subprogram
# declarations inside the statement part (i.e. after `begin`), so
# the walker after the matching `begin` only has to skip
# body-construct ends.
proc ::aurig::core::analyze::_find_subprogram_end {text kwStart} {
    set N [string length $text]

    # Step 1: skip past the subprogram keyword
    lassign [::aurig::core::analyze::_nextw $text $kwStart] kwW kwS kwE
    set afterKw [expr {$kwE + 1}]

    # Step 2: find the matching `begin` (depth-aware, skips nested
    # subprogram declarations in the outer's declarative part).
    set bS [::aurig::core::analyze::_find_decl_body_begin $text $afterKw -1]
    if {$bS < 0} { return -1 }
    set i [expr {$bS + 5}]

    # Step 3: walk forward looking for the subprogram-closing
    # `end ... ;`. Skip body-construct ends (end if;, end loop;, etc).
    while {$i < $N} {
        if {![regexp -indices -start $i -nocase {\mend\M} $text endIdx]} {
            return -1
        }
        lassign $endIdx endKwS endKwE
        lassign [::aurig::core::analyze::_peek2w_stop_at_semicolon $text $endKwE] \
            w2 s2 e2 w3 s3 e3
        set kw2 [string tolower $w2]
        # Subprogram closes if next word is empty (`end;`), an
        # explicit `function`/`procedure` keyword (`end function;`,
        # `end function NAME;`), or any identifier that is NOT a
        # body-construct keyword (`end NAME;`).
        if {$w2 eq ""} {
            return [::aurig::core::analyze::_find_vhdl_statement_semicolon $text $endKwS]
        }
        if {$kw2 in {function procedure package protected}} {
            return [::aurig::core::analyze::_find_vhdl_statement_semicolon $text $endKwS]
        }
        if {$kw2 in {if loop case generate process record block
                     units for while view component}} {
            # Body-construct end; advance past its ';' and continue.
            set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $text $endKwS]
            if {$semi < 0} { return -1 }
            set i [expr {$semi + 1}]
            continue
        }
        # Else: `end NAME;` where NAME is the subprogram name.
        return [::aurig::core::analyze::_find_vhdl_statement_semicolon $text $endKwS]
    }
    return -1
}

proc ::aurig::core::analyze::_mask_subprograms {decl} {
    set masked $decl

    # Pass 1: subprograms with body. Token-based walker per
    # `function`/`procedure` keyword to avoid the Tcl ARE
    # leftmost-longest over-match trap — see _find_subprogram_end
    # above for the rationale.
    set start 0
    while {[regexp -indices -start $start -nocase {\m(function|procedure)\M} $masked kwIdx]} {
        lassign $kwIdx kwS kwE
        set semiEnd [::aurig::core::analyze::_find_subprogram_end $masked $kwS]
        if {$semiEnd < 0} {
            # Not a definition (likely a prototype) — leave for Pass 2.
            set start [expr {$kwE + 1}]
            continue
        }
        set spanLen [expr {$semiEnd - $kwS + 1}]
        set spaces [string repeat " " $spanLen]
        set masked [string replace $masked $kwS $semiEnd $spaces]
        set start [expr {$semiEnd + 1}]
    }

    # Pass 2: subprogram prototypes (no body). Search on the already-masked
    # text so we don't re-find bodies' keywords (now spaces).
    set start 0
    while {[regexp -indices -start $start -nocase {\m(function|procedure)\M} $masked kwIdx]} {
        lassign $kwIdx kwS kwE
        set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $kwS]
        if {$semi < 0} {
            set start [expr {$kwE + 1}]
            continue
        }
        set spanLen [expr {$semi - $kwS + 1}]
        set spaces [string repeat " " $spanLen]
        set masked [string replace $masked $kwS $semi $spaces]
        set start [expr {$semi + 1}]
    }

    return $masked
}

# ---------------------------------
# Scan variable declarations in an architecture declarative part.
# - Works like your signal scanner.
# - Subprograms are masked out first, so no false positives inside them.
# ---------------------------------
proc ::aurig::core::analyze::_scan_architecture_variables {decl n} {
    set results {}
    set masked [::aurig::core::analyze::_mask_subprograms $decl]

    set N   [string length $masked]
    set idx 0

    while {$idx < $N} {
        if {![regexp -indices -start $idx -nocase {\mvariable\s+} $masked matchIdx]} {
            break
        }
        lassign $matchIdx mStart mEnd
        set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $mStart]
        if {$semi < 0} {
            set idx [expr {$mEnd + 1}]
            continue
        }

        set stmt [string range $decl $mStart [expr {$semi - 1}]]
        if {![regexp -indices -nocase {^variable\s+(.+?)\s*:\s*(.*)$} $stmt -> namesRelIdx tailRelIdx]} {
            set idx [expr {$semi + 1}]
            continue
        }
        lassign $namesRelIdx nRelStart nRelEnd
        lassign $tailRelIdx  tRelStart tRelEnd
        set namesChunk [string range $stmt $nRelStart $nRelEnd]
        set tailChunk  [string range $stmt $tRelStart $tRelEnd]

        # Line points at the first character of the name list (legacy semantics).
        set line [::aurig::core::analyze::_index_to_line $decl [expr {$mStart + $nRelStart}] $n]

        # Split names by comma
        set nameList {}
        foreach raw [split $namesChunk ,] {
            set nm [string trim $raw]
            if {$nm ne {}} { lappend nameList $nm }
        }

        # Split type / optional init on the FIRST ':=' token
        set div [string first ":=" $tailChunk]
        if {$div < 0} {
            set varType [string trim $tailChunk]
            set varInit {}
        } else {
            set varType [string trim [string range $tailChunk 0 [expr {$div-1}]]]
            set varInit [string trim [string range $tailChunk [expr {$div+2}] end]]
        }

        foreach varName $nameList {
            lappend results [dict create \
                name $varName \
                type $varType \
                init $varInit \
                line $line]
        }

        set idx [expr {$semi + 1}]
    }

    return $results
}

# ---------------------------------
# Scan constant declarations in an architecture declarative part.
# - Skips constants inside functions/procedures by masking them first.
# - Supports multiple names, first ':=' token for init, and stops at first ';'.
# ---------------------------------
proc ::aurig::core::analyze::_scan_architecture_constants {decl n {commentDict {}}} {
    set results {}
    # Reuse your subprogram masker so we ignore constants inside subprograms
    set masked [::aurig::core::analyze::_mask_subprograms $decl]

    set N   [string length $masked]
    set idx 0
    
    # Track last comment line used to prevent duplication
    set lastUsedCommentLine -99

    while {$idx < $N} {
        if {![regexp -indices -start $idx -nocase {\mconstant\s+} $masked matchIdx]} {
            break
        }
        lassign $matchIdx mStart mEnd
        set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $mStart]
        if {$semi < 0} {
            set idx [expr {$mEnd + 1}]
            continue
        }

        set stmt [string range $decl $mStart [expr {$semi - 1}]]
        if {![regexp -indices -nocase {^constant\s+(.+?)\s*:\s*(.*)$} $stmt -> namesRelIdx tailRelIdx]} {
            set idx [expr {$semi + 1}]
            continue
        }
        lassign $namesRelIdx nRelStart nRelEnd
        lassign $tailRelIdx  tRelStart tRelEnd
        set namesChunk [string range $stmt $nRelStart $nRelEnd]
        set tailChunk  [string range $stmt $tRelStart $tRelEnd]

        # Line points at the first character of the name list (legacy semantics).
        set line [::aurig::core::analyze::_index_to_line $decl [expr {$mStart + $nRelStart}] $n]

        # Split name list by comma
        set nameList {}
        foreach raw [split $namesChunk ,] {
            set nm [string trim $raw]
            if {$nm ne {}} { lappend nameList $nm }
        }

        # Split type / optional init on the FIRST ':=' token
        set div [string first ":=" $tailChunk]
        if {$div < 0} {
            set constType [string trim $tailChunk]
            set constInit {}
        } else {
            set constType [string trim [string range $tailChunk 0 [expr {$div-1}]]]
            set constInit [string trim [string range $tailChunk [expr {$div+2}] end]]
        }
        
        # Extract comment from commentDict - search back up to 5 lines
        # Only use comments that haven't been used for previous constants
        set constComment ""
        set foundCommentLine -1
        if {[llength $commentDict] > 0} {
            # Search backwards for a comment (skip separator lines)
            for {set i 2} {$i <= 6} {incr i} {
                set commentLine [expr {$line - $i}]
                if {[dict exists $commentDict $commentLine]} {
                    set commentEntry [dict get $commentDict $commentLine]
                    if {[dict exists $commentEntry comment]} {
                        set rawComment [dict get $commentEntry comment]
                    } else {
                        set rawComment $commentEntry
                    }
                    # Skip separator lines
                    if {![regexp {^[-=*#]{5,}} $rawComment]} {
                        # Check for descriptive comments (allowing + prefix)
                        if {[string length [string trim $rawComment]] > 5 || [regexp {^[*@+]} $rawComment]} {
                            set foundCommentLine $commentLine
                            # Only use this comment if it wasn't already used for a previous constant
                            if {$foundCommentLine != $lastUsedCommentLine} {
                                set constComment [string trim $rawComment]
                                set lastUsedCommentLine $foundCommentLine
                            }
                            break
                        }
                    }
                }
            }
        }

        # Emit one dict per constant
        foreach constName $nameList {
            set item [dict create \
                name $constName \
                type $constType \
                init $constInit \
                line $line]
            if {$constComment ne ""} {
                dict set item comment $constComment
            }
            lappend results $item
        }

        set idx [expr {$semi + 1}]
    }

    return $results
}

# ---------------------------------
# Scan type and subtype declarations in an architecture / package
# declarative part. LINT-PARSER-DEBT-022 — re-enables what used to
# live as an archived regex block in `analyze/vhdlscan.tcl`, but
# rewritten as a token-aware dispatcher instead of one big regex.
# Subprograms are masked first, so a type declared inside a function
# body is not seen here (it would belong to a future body-types
# extension if ever needed).
#
# Returns a list of dicts with at minimum {kind name line}. `kind`
# is `type` for `type ... is ...;` and `subtype` for `subtype ... is
# ...;`. For `type`, an additional `subtype_kind` field identifies
# the form — enumerated / integer_range / physical / array / record.
# ---------------------------------
proc ::aurig::core::analyze::_scan_architecture_types {decl n {commentDict {}}} {
    set results {}
    set masked [::aurig::core::analyze::_mask_subprograms $decl]
    set N [string length $masked]
    set idx 0

    while {$idx < $N} {
        # Find next `(sub)?type NAME is` header.
        if {![regexp -indices -start $idx -nocase \
                {\m(type|subtype)\s+([a-zA-Z]\w*)\s+is\M} \
                $masked m kwIdx nameIdx]} {
            break
        }
        lassign $m mStart mEnd
        lassign $kwIdx kwS kwE
        lassign $nameIdx nStart nEnd
        set kw       [string tolower [string range $masked $kwS $kwE]]
        set typeName [string range $decl $nStart $nEnd]
        set line     [::aurig::core::analyze::_index_to_line $decl $nStart $n]

        set bodyStart  [expr {$mEnd + 1}]
        set subtypeKind ""
        set semiEnd    -1

        if {$kw eq "subtype"} {
            # Subtype indication followed by a single ';'.
            set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $bodyStart]
            if {$semi < 0} {
                set idx [expr {$mEnd + 1}]
                continue
            }
            set semiEnd $semi
        } else {
            # Dispatch on the first non-whitespace token after `is`.
            set i $bodyStart
            while {$i < $N && [string is space -strict [string index $masked $i]]} {
                incr i
            }
            if {$i >= $N} {
                set idx [expr {$mEnd + 1}]
                continue
            }
            set ch [string index $masked $i]
            if {$ch eq "("} {
                # Enumerated type: (literal_list) ;
                set subtypeKind "enumerated"
                if {[catch {::aurig::core::analyze::_grab_paren_block $masked $i} blk]} {
                    set idx [expr {$mEnd + 1}]
                    continue
                }
                set afterParen [dict get $blk next]
                set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $afterParen]
                if {$semi < 0} {
                    set idx [expr {$mEnd + 1}]
                    continue
                }
                set semiEnd $semi
            } else {
                lassign [::aurig::core::analyze::_nextw $masked $i] w wS wE
                set lw [string tolower $w]
                if {$lw eq "range"} {
                    # Integer-range OR physical (range ... units ... end units;).
                    set firstSemi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $i]
                    if {$firstSemi < 0} {
                        set idx [expr {$mEnd + 1}]
                        continue
                    }
                    set headerText [string range $masked $i $firstSemi]
                    if {[regexp -nocase {\munits\M} $headerText]} {
                        set subtypeKind "physical"
                        set endSemi [::aurig::core::analyze::_find_keyword_end_semi $masked $i units]
                        if {$endSemi < 0} {
                            set idx [expr {$mEnd + 1}]
                            continue
                        }
                        set semiEnd $endSemi
                    } else {
                        set subtypeKind "integer_range"
                        set semiEnd $firstSemi
                    }
                } elseif {$lw eq "array"} {
                    set subtypeKind "array"
                    set semi [::aurig::core::analyze::_find_vhdl_statement_semicolon $masked $i]
                    if {$semi < 0} {
                        set idx [expr {$mEnd + 1}]
                        continue
                    }
                    set semiEnd $semi
                } elseif {$lw eq "record"} {
                    set subtypeKind "record"
                    set endSemi [::aurig::core::analyze::_find_keyword_end_semi $masked [expr {$wE + 1}] record]
                    if {$endSemi < 0} {
                        set idx [expr {$mEnd + 1}]
                        continue
                    }
                    set semiEnd $endSemi
                } else {
                    # Unknown / unsupported form (e.g. access, file,
                    # protected). Skip past the header and keep
                    # scanning for the next type declaration.
                    set idx [expr {$mEnd + 1}]
                    continue
                }
            }
        }

        set item [dict create \
            kind $kw \
            name $typeName \
            line $line]
        if {$subtypeKind ne ""} {
            dict set item subtype_kind $subtypeKind
        }
        lappend results $item

        set idx [expr {$semiEnd + 1}]
    }

    return $results
}

# Find the ';' that closes a VHDL block opener like `record` or
# `units`. Given an index inside the body, walks forward looking
# for the next `end <keyword> [ NAME ];` and returns the index of
# the closing ';', or -1 if not found. No nesting tracking — VHDL
# does not allow anonymous nested records / units inside a single
# type declaration, so the first matching `end <keyword>` is
# always the right one. Body-construct ends like `end if;` /
# `end loop;` (which can appear inside a record's field
# initialisers? — no, only in subprograms which are masked
# upstream) are skipped over.
proc ::aurig::core::analyze::_find_keyword_end_semi {text startIdx endKw} {
    set N [string length $text]
    set i $startIdx
    while {$i < $N} {
        if {![regexp -indices -start $i -nocase {\mend\M} $text mIdx]} {
            return -1
        }
        lassign $mIdx mS mE
        lassign [::aurig::core::analyze::_nextw $text [expr {$mE + 1}]] w2 s2 e2
        if {[string tolower $w2] eq $endKw} {
            return [::aurig::core::analyze::_find_vhdl_statement_semicolon $text $mS]
        }
        set i [expr {$mE + 1}]
    }
    return -1
}

# --------------------------------
# Scan function declarations in a declarative part
# Matches patterns like:
#   function name(params) return type;
#   pure function name(params) return type;
#   impure function name(params) return type;
# Also matches function definitions (with 'is' instead of ';') to capture signatures
# --------------------------------
proc ::aurig::core::analyze::_scan_functions {decl n {commentDict {}}} {
    set results {}
    
    # Don't mask for function search - we want to find function signatures even for definitions
    set N [string length $decl]
    set idx 0
    
    # Match function keyword, name, then a delimiter that is either the
    # parameter-list opening paren OR the `return` keyword (for
    # parameterless functions like `function seed return integer is ...`).
    # LINT-RULES-DEBT-039 review: the old regex required `\s*\(` after
    # the name, so parameterless functions — legal VHDL — were silently
    # dropped. The 3rd capture group (`delim`) tells us which form was
    # matched and we branch accordingly below.
    # (?i) = case insensitive; \m = start of word; \M = end of word
    set re {(?i)\m(pure\s+|impure\s+)?function\s+([a-zA-Z]\w*)\s*(\(|return\M)}

    while {$idx < $N} {
        if {![regexp -indices -start $idx $re $decl -> purityIdx nameIdx delimIdx]} {
            break
        }

        lassign $nameIdx nStart nEnd
        set funcName [string range $decl $nStart $nEnd]
        set delim [string range $decl [lindex $delimIdx 0] [lindex $delimIdx 1]]

        # Determine purity
        set purity "pure"
        if {[lindex $purityIdx 0] >= 0} {
            set purityText [string trim [string range $decl [lindex $purityIdx 0] [lindex $purityIdx 1]]]
            if {[string match -nocase "impure*" $purityText]} {
                set purity "impure"
            }
        }

        if {$delim eq "("} {
            # Parametric form: parse the param list as before.
            set parenStart [expr {[lindex $delimIdx 0] + 1}]

            # Manually parse to find matching closing paren (handle nested parens)
            set parenDepth 1
            set parenEnd -1
            for {set i $parenStart} {$i < $N} {incr i} {
                set char [string index $decl $i]
                if {$char eq "("} {
                    incr parenDepth
                } elseif {$char eq ")"} {
                    incr parenDepth -1
                    if {$parenDepth == 0} {
                        set parenEnd [expr {$i - 1}]
                        break
                    }
                }
            }

            if {$parenEnd < 0} {
                # No matching closing paren found
                set idx [expr {$nEnd + 1}]
                continue
            }

            set paramsChunk [string range $decl $parenStart $parenEnd]
            set paramsList [string trim $paramsChunk]
            set returnSearchStart [expr {$parenEnd + 2}]
        } else {
            # Parameterless form: delim matched "return", so the params
            # list is empty and the return-type scan resumes at the
            # start of the matched "return" keyword (the existing
            # `\s+return\s+...` regex below requires at least one
            # whitespace BEFORE `return`, so we point the search one
            # character before the delim to satisfy the leading `\s+`).
            set paramsList ""
            set returnSearchStart [lindex $delimIdx 0]
            if {$returnSearchStart > 0} {
                incr returnSearchStart -1
            }
        }

        # Find "return" keyword (or its tail in the parameterless path).
        # PR #106 review: the alternation was `(;|is\b)` but in Tcl ARE
        # `\b` is the backspace character (ASCII 8), not a word boundary
        # — the `is\b` branch was dead. Fixed to `is\M` (end-of-word)
        # for correctness; this does NOT change runtime behaviour
        # (verified empirically: Tcl ARE's leftmost-longest preference
        # still picks the `;` alternative because that match consumes
        # more characters), but it makes the alternation semantically
        # honest and removes a misleading inline construct. The
        # body-declaration extraction below continues to detect `is`
        # by searching returnChunk via the inner `\s+is\M` regex —
        # that path is the canonical discriminator for definition vs
        # prototype, as documented at the body-decl block.
        set afterParen $returnSearchStart
        if {![regexp -indices -start $afterParen -nocase {\s+return\s+([^;]+?)\s*(;|is\M)} $decl -> returnIdx endIdx]} {
            # No return type found
            set idx [expr {$nEnd + 1}]
            continue
        }
        
        lassign $returnIdx rStart rEnd
        set returnType [string trim [string range $decl $rStart $rEnd]]
        
        # Clean return type - remove everything after 'is' if present (for function definitions)
        if {[regexp -nocase {\s+is\s} $returnType]} {
            set returnType [string trim [regsub -nocase {\s+is\s.*$} $returnType ""]]
        }
        
        # Approximate line number
        set line [::aurig::core::analyze::_index_to_line $decl $nStart $n]
        
        # Extract comment from commentDict
        # Only collect complete documentation blocks (with @brief)
        set funcComment ""
        if {[llength $commentDict] > 0} {
            set commentLines {}
            set checkLine [expr {$line - 1}]
            
            # First check if there's an inline comment on the function declaration line itself
            set inlineComment ""
            if {[dict exists $commentDict $line]} {
                set commentEntry [dict get $commentDict $line]
                if {[dict exists $commentEntry comment]} {
                    set inlineComment [dict get $commentEntry comment]
                } else {
                    set inlineComment $commentEntry
                }
                set inlineComment [string trim $inlineComment]
            }
            
            # Collect consecutive comment lines going backward from line-1
            # Stop at separator, very short comments, or empty lines
            for {set i 0} {$i < 15} {incr i} {
                set searchLine [expr {$checkLine - $i}]
                if {[dict exists $commentDict $searchLine]} {
                    set commentEntry [dict get $commentDict $searchLine]
                    if {[dict exists $commentEntry comment]} {
                        set rawComment [dict get $commentEntry comment]
                    } else {
                        set rawComment $commentEntry
                    }
                    set trimmedComment [string trim $rawComment]
                    
                    # Check if it's a pure separator line (5+ separator chars)
                    if {[regexp {^[-=*#_]{5,}\s*$} $trimmedComment]} {
                        # Found separator - stop
                        break
                    } elseif {[string length $trimmedComment] <= 3} {
                        # Very short comment (like "3", "4") - likely inline marker
                        break
                    } else {
                        # Add comment
                        lappend commentLines $rawComment
                    }
                } else {
                    # No comment on this line - stop
                    break
                }
            }
            
            # Reverse what we collected (since we went backward)
            if {[llength $commentLines] > 0} {
                set commentLines [lreverse $commentLines]
                set fullComment [join $commentLines "\n"]
                
                # Only use block comment if it has @brief (complete documentation)
                # Partial blocks (just "@param" or "Example:") indicate line number offset issues
                if {[regexp {@brief} $fullComment]} {
                    set funcComment $fullComment
                } elseif {$inlineComment ne "" && [string length $inlineComment] <= 50} {
                    # Block doesn't have @brief, use short inline comment instead
                    set funcComment $inlineComment
                }
                # Otherwise leave funcComment empty (incomplete block, no valid inline)
            } elseif {$inlineComment ne "" && [string length $inlineComment] <= 50} {
                # No block comment found, use inline comment if short enough
                set funcComment $inlineComment
            }
        }
        
        # Create result dict
        set item [dict create \
            name $funcName \
            return $returnType \
            params $paramsList \
            purity $purity \
            line $line]

        if {$funcComment ne ""} {
            dict set item comment $funcComment
        }

        # Surface variable / constant declarations inside the function
        # body's declarative part if this is a definition (the return
        # group's raw text contains a trailing ' is' before the body)
        # — LINT-PARSER-DEBT-021. Note that the outer regex's
        # `(;|is\M)` alternative is NOT a reliable discriminator here:
        # Tcl ARE picks the LONGEST match (leftmost-longest), so the
        # trailing ';' inside the function body still wins over the
        # earlier `is` keyword and returnChunk extends through the
        # body. The inner `\s+is\M` probe on returnChunk below is the
        # canonical way to locate the `is` keyword. (PR #106 review
        # fixed the outer alternative from the dead `is\b`
        # — backspace character in Tcl ARE — to `is\M`; behaviour
        # unchanged but the alternative is now semantically valid.)
        set rStart [lindex $returnIdx 0]
        set rEnd   [lindex $returnIdx 1]
        set returnChunk [string range $decl $rStart $rEnd]
        set isInChunk -1
        if {[regexp -nocase -indices {\s+is\M} $returnChunk isMatch]} {
            set isInChunk [lindex $isMatch 1]
        }
        if {$isInChunk >= 0} {
            set afterIs [expr {$rStart + $isInChunk + 1}]
            set bS [::aurig::core::analyze::_find_decl_body_begin $decl $afterIs -1]
            if {$bS > $afterIs} {
                set sub_decl_raw  [string range $decl $afterIs [expr {$bS - 1}]]
                set sub_base_line [::aurig::core::analyze::_index_to_line $decl $afterIs $n]
                set body_decls {}
                foreach v [::aurig::core::analyze::_scan_architecture_variables $sub_decl_raw $sub_base_line] {
                    lappend body_decls [dict create \
                        kind variable \
                        name [dict get $v name] \
                        type [dict get $v type] \
                        init [dict get $v init] \
                        line [dict get $v line]]
                }
                foreach c [::aurig::core::analyze::_scan_architecture_constants $sub_decl_raw $sub_base_line] {
                    lappend body_decls [dict create \
                        kind constant \
                        name [dict get $c name] \
                        type [dict get $c type] \
                        init [dict get $c init] \
                        line [dict get $c line]]
                }
                if {[llength $body_decls]} {
                    dict set item body_declarations $body_decls
                }
            }
        }

        lappend results $item

        # Advance past the end of return type declaration
        set idx [expr {[lindex $endIdx 1] + 1}]
    }

    return $results
}

# --------------------------------
# Scan procedure declarations in a declarative part
# Matches patterns like:
#   procedure name(params);
#   procedure name(params) is
# --------------------------------
proc ::aurig::core::analyze::_scan_procedures {decl n {commentDict {}}} {
    set results {}
    
    set N [string length $decl]
    set idx 0
    
    # Match procedure keyword and name, then a delimiter that is
    # either the param-list opening paren OR the `is` keyword
    # (definition with body, parameterless form).
    # LINT-RULES-DEBT-039 review: the old regex required `\s*\(`
    # after the name, so parameterless procedure DEFINITIONS — legal
    # VHDL — were silently dropped. Note we deliberately do NOT add
    # `;` as a third alternative: that would falsely match the
    # closing `end procedure NAME;` of EVERY procedure, producing
    # spurious duplicate entries. Parameterless procedure prototypes
    # (`procedure foo;` in a package spec, no `is`-body) remain
    # uncaptured by this scanner — an acceptable loss outside the
    # eo_cpu / LINT-RULES-DEBT-039 use case, which is definitions
    # inside a `package body`.
    # (?i) = case insensitive
    set re {(?i)\mprocedure\s+([a-zA-Z]\w*)\s*(\(|is\M)}

    while {$idx < $N} {
        if {![regexp -indices -start $idx $re $decl -> nameIdx delimIdx]} {
            break
        }

        lassign $nameIdx nStart nEnd
        set procName [string range $decl $nStart $nEnd]
        set delim [string range $decl [lindex $delimIdx 0] [lindex $delimIdx 1]]

        if {$delim eq "("} {
            # Parametric form: walk param list as before.
            set parenStart [expr {[lindex $delimIdx 0] + 1}]
            set parenDepth 1
            set parenEnd -1
            for {set i $parenStart} {$i < $N} {incr i} {
                set char [string index $decl $i]
                if {$char eq "("} {
                    incr parenDepth
                } elseif {$char eq ")"} {
                    incr parenDepth -1
                    if {$parenDepth == 0} {
                        set parenEnd [expr {$i - 1}]
                        break
                    }
                }
            }

            if {$parenEnd < 0} {
                # No matching closing paren found
                set idx [expr {$nEnd + 1}]
                continue
            }

            set paramsChunk [string range $decl $parenStart $parenEnd]
            set paramsList [string trim $paramsChunk]
            set bodyScanStart [expr {$parenEnd + 2}]
            # End of consumed prefix — used to advance the outer loop
            # past this match. For parametric: past the closing paren.
            set matchAdvance $bodyScanStart
        } else {
            # Parameterless DEFINITION form (delim is `is`): no
            # params; body scan resumes at the delim start so the
            # existing `^\s*is\M` regex below picks it up.
            set paramsList ""
            set bodyScanStart [lindex $delimIdx 0]
            # Advance past the `is` so the outer loop does not
            # re-match the same procedure header on its next
            # iteration.
            set matchAdvance [expr {[lindex $delimIdx 1] + 1}]
        }
        
        # Calculate line number (count newlines up to match start)
        set offset [lindex $nameIdx 0]
        set prefix [string range $decl 0 [expr {$offset - 1}]]
        set line [expr {$n + [regexp -all {\n} $prefix] + 1}]
        
        # Search for comment - aggregate consecutive comment lines immediately above AND at the procedure line
        # Collect all consecutive comments going backward, then forward to get full block
        set procComment ""
        set commentLines {}
        set checkLine [expr {$line - 1}]
        
        # Collect consecutive comment lines going backward from line-1
        # Stop immediately if we hit a line with no comment
        for {set i 0} {$i < 15} {incr i} {
            set scanLine [expr {$checkLine - $i}]
            if {[dict exists $commentDict $scanLine]} {
                set commentEntry [dict get $commentDict $scanLine]
                if {[dict exists $commentEntry comment]} {
                    set cmt [dict get $commentEntry comment]
                } else {
                    set cmt $commentEntry
                }
                # Check if it's a separator
                if {[regexp {^[-=*#_]{5,}\s*$} $cmt]} {
                    # Found separator - if we have comments, stop; otherwise continue
                    if {[llength $commentLines] > 0} {
                        break
                    }
                } else {
                    # Substantive comment (even if short/empty like "*")
                    lappend commentLines $cmt
                }
            } else {
                # No comment on this line - ALWAYS stop (don't skip gaps)
                break
            }
        }
        
        # Reverse what we collected (since we went backward)
        if {[llength $commentLines] > 0} {
            set commentLines [lreverse $commentLines]
        }
        
        # Don't collect forward - causes duplication. Only use backward collection.
        # The line number calculation is accurate enough.
        
        # Join all collected lines
        if {[llength $commentLines] > 0} {
            set procComment [join $commentLines "\n"]
        }
        
        set item [dict create \
            kind procedure \
            name $procName \
            params $paramsList \
            line $line]

        if {$procComment ne ""} {
            dict set item comment $procComment
        }

        # Surface variable / constant declarations inside the
        # procedure body's declarative part if this is a definition
        # (header followed by 'is'), not a prototype (followed by
        # ';') — LINT-PARSER-DEBT-021. Mirrors the logic in
        # _scan_functions above. `$bodyScanStart` was set above to
        # the position right after the param-list close paren (for
        # parametric) or to the delim start (for parameterless),
        # so the `^\s*is\M` check below covers both cases uniformly.
        set afterParen $bodyScanStart
        set restRange  [string range $decl $afterParen end]
        # Use \M (end-of-word) instead of \b: in Tcl ARE \b is the
        # backspace character, not a word boundary.
        if {[regexp -nocase -indices {^\s*is\M} $restRange isMatch]} {
            set afterIs [expr {$afterParen + [lindex $isMatch 1] + 1}]
            set bS [::aurig::core::analyze::_find_decl_body_begin $decl $afterIs -1]
            if {$bS > $afterIs} {
                set sub_decl_raw  [string range $decl $afterIs [expr {$bS - 1}]]
                set sub_base_line [::aurig::core::analyze::_index_to_line $decl $afterIs $n]
                set body_decls {}
                foreach v [::aurig::core::analyze::_scan_architecture_variables $sub_decl_raw $sub_base_line] {
                    lappend body_decls [dict create \
                        kind variable \
                        name [dict get $v name] \
                        type [dict get $v type] \
                        init [dict get $v init] \
                        line [dict get $v line]]
                }
                foreach c [::aurig::core::analyze::_scan_architecture_constants $sub_decl_raw $sub_base_line] {
                    lappend body_decls [dict create \
                        kind constant \
                        name [dict get $c name] \
                        type [dict get $c type] \
                        init [dict get $c init] \
                        line [dict get $c line]]
                }
                if {[llength $body_decls]} {
                    dict set item body_declarations $body_decls
                }
            }
        }

        lappend results $item

        # Advance past the header we just consumed (parametric path:
        # past the closing paren; parameterless path: past the `is`
        # or `;` delim).
        set idx $matchAdvance
    }

    return $results
}

# --------------------------------
# PUBLIC API
# --------------------------------
# Usage: parse_architecture_body localDictVar $archBody $n
proc ::aurig::core::analyze::parse_architecture_body {localDictVar archBody n} {
    upvar 1 $localDictVar D

    # keep line count stable; just normalize tabs & trailing spaces
    # set body [::aurig::core::analyze::_normalize_ws_keep_lines $archBody]
    set body $archBody
    
    # Extract comment dict if available
    set commentDict {}
    if {[dict exists $D comments line]} {
        set commentDict [dict get $D comments line]
    }
    
    # scan & push
    foreach I [::aurig::core::analyze::_scan_instantiations $body $n $commentDict] {
        set D [::aurig::core::analyze::_push_into_last_arch $D instantiations $I]
    }
    foreach G [::aurig::core::analyze::_scan_generates $body $n] {
        set D [::aurig::core::analyze::_push_into_last_arch $D generates $G]
    }
    foreach B [::aurig::core::analyze::_scan_blocks $body $n] {
        set D [::aurig::core::analyze::_push_into_last_arch $D blocks $B]
    }
    foreach P [::aurig::core::analyze::_scan_processes $body $n $commentDict] {
        set D [::aurig::core::analyze::_push_into_last_arch $D processes $P]
    }
    return
}

# --------------------------------
# Scan generate statements (if/for forms)
# Captures label, scheme (if|for), condition/loop details, body slice, line
# Supports:
#   - if-generate with condition
#   - for-generate with loop_var and loop_range
#   - labeled and unlabeled forms
#   - generates with or without 'begin' keyword
#   - nested generates (body contains nested generate text, not parsed recursively)
# --------------------------------
proc ::aurig::core::analyze::_scan_generates {body n} {
    set results {}
    set idx 0
    set N [string length $body]
    while {$idx < $N} {
        # Look for either labeled or unlabeled generate headers
        # Forms:
        #   lbl : if (<cond>) generate
        #   lbl : for <var> in <range> generate
        #   if (<cond>) generate
        #   for <var> in <range> generate
        # Note: Use \m and \M for Tcl word boundaries
        if {![regexp -indices -nocase -start $idx {(?:\m(\w+)\M\s*:\s*)?\m(if|for)\M} $body mIdx lblIdx schemeIdx]} {
            break
        }
        lassign $mIdx mStart mEnd
        # Extract optional label
        # lblIdx captures just the label identifier (without the colon)
        # Check if lblIdx indicates a valid match (both indices >= 0)
        set label ""
        if {[lindex $lblIdx 0] >= 0 && [lindex $lblIdx 1] >= 0} {
            set label [string range $body [lindex $lblIdx 0] [lindex $lblIdx 1]]
        }
        set scheme [string tolower [string range $body [lindex $schemeIdx 0] [lindex $schemeIdx 1]]]

        # Ensure this header actually leads to a 'generate' (may be a process or other)
        # Search forward for 'generate' keyword - must be before any semicolon
        set genPos -1
        if {[regexp -indices -nocase -start $mEnd -- $::aurig::core::util::re::re_generate_kw $body gIdx]} {
            set candidateGenPos [lindex $gIdx 0]
            set semiRel [string first ";" [string range $body $mEnd end]]
            set semiPos -1
            if {$semiRel >= 0} {
                set semiPos [expr {$mEnd + $semiRel}]
            }
            if {$semiPos < 0 || $candidateGenPos < $semiPos} {
                set genPos $candidateGenPos
            }
        }
        if {$genPos < 0} { set idx [expr {$mEnd+1}]; continue }

        # Find matching 'end generate' by tracking nested generate depth
        # Start at depth 1 (for this generate), look for depth to return to 0
        set genDepth 1
        set endStart -1
        set semi -1
        set searchPos [expr {$genPos + 9}]  ;# Start right after 'generate' keyword
        
        
        while {$searchPos < $N && $genDepth > 0} {
            # Find next 'generate' or 'end generate'
            set nextGen -1
            set nextEndGen -1
            
            if {[regexp -indices -nocase -start $searchPos -- $::aurig::core::util::re::re_generate_kw $body gIdx]} {
                set nextGen [lindex $gIdx 0]
            }
            if {[regexp -indices -nocase -start $searchPos -- $::aurig::core::util::re::re_end_generate_kw $body egIdx]} {
                set nextEndGen [lindex $egIdx 0]
            }
            
            
            # Process the one that comes first
            if {$nextGen >= 0 && ($nextEndGen < 0 || $nextGen < $nextEndGen)} {
                # Found a nested 'generate'
                incr genDepth
                set searchPos [expr {$nextGen + 9}]
            } elseif {$nextEndGen >= 0} {
                # Found an 'end generate'
                incr genDepth -1
                if {$genDepth == 0} {
                    # This is the matching end for our generate
                    set endStart $nextEndGen
                    # Find semicolon after 'end generate'
                    set semiPos [string first ";" [string range $body $endStart end]]
                    if {$semiPos >= 0} {
                        set semi [expr {$endStart + $semiPos}]
                    }
                    break
                }
                # Move past 'end generate'
                set searchPos [expr {$nextEndGen + 13}]
            } else {
                # No more generate/end-generate found
                break
            }
        }
        
        if {$endStart < 0 || $semi < 0} { 
            set idx [expr {$mEnd+1}]; 
            continue 
        }

        # Parse condition/loop details between scheme token and 'generate'
        set condStart [lindex $schemeIdx 1]
        set headerText [string trim [string range $body [expr {$condStart+1}] [expr {$genPos-1}]]]
        
        # Initialize fields
        set condition ""
        set loop_var ""
        set loop_range ""
        
        if {$scheme eq "if"} {
            # For if-generate: condition is the headerText (may include parens)
            set condition $headerText
            # Strip outer parentheses if present
            if {[regexp {^\s*\((.*)\)\s*$} $condition -> inner]} {
                set condition [string trim $inner]
            }
        } elseif {$scheme eq "for"} {
            # For for-generate: parse "<var> in <range>"
            # Examples: "i in 0 to 7", "idx in G_WIDTH-1 downto 0"
            if {[regexp -nocase {^\s*(\w+)\s+in\s+(.+)\s*$} $headerText -> var range]} {
                set loop_var [string trim $var]
                set loop_range [string trim $range]
                # Store entire header as condition for backward compatibility
                set condition $headerText
            } else {
                # Fallback if parsing fails
                set condition $headerText
            }
        }

        # Extract body between 'generate' keyword and 'end generate'
        # Body may or may not have 'begin' keyword
        set genEnd [expr {$genPos + 9}]  ;# Position after 'generate' keyword
        set bodyTxt ""
        
        # Check if there's a 'begin' immediately after 'generate' (before any statement)
        set searchChunk [string range $body $genEnd $endStart]
        # Only look for begin at the start of the generate body (skip whitespace)
        if {[regexp -indices -nocase {^\s*\mbegin\M} $searchChunk bIdx]} {
            # Found 'begin' right after 'generate', extract from after 'begin' to before 'end generate'
            set beginEnd [lindex $bIdx 1]
            set bodyStart [expr {$genEnd + $beginEnd + 1}]
            set bodyTxt [string trim [string range $body $bodyStart [expr {$endStart - 1}]]]
        } else {
            # No 'begin', extract from after 'generate' to before 'end generate'
            set bodyTxt [string trim [string range $body $genEnd [expr {$endStart - 1}]]]
        }

        set line [::aurig::core::analyze::_index_to_line $body $mStart $n]
        
        # Build item dict with all fields including offsets for precise text manipulation
        set item [dict create \
            label $label \
            scheme $scheme \
            condition $condition \
            body $bodyTxt \
            line $line \
            start_offset $mStart \
            header_end_offset [expr {$genPos + 8}] \
            end_offset $semi]
        
        # Add for-generate specific fields if present
        if {$loop_var ne ""} {
            dict set item loop_var $loop_var
            dict set item loop_range $loop_range
        }
        
        lappend results $item
        set idx [expr {$semi+1}]
    }
    return $results
}

# --------------------------------
# Scan block statements: '<label> : block [guard] is ... begin ... end block [label];'
# Captures label, optional guard, body, line
# --------------------------------
proc ::aurig::core::analyze::_scan_blocks {body n} {
    set results {}
    set idx 0
    set N [string length $body]
    while {$idx < $N} {
        if {![regexp -indices -nocase -start $idx {\m(\w+)\M\s*:\s*block\b} $body mIdx labelIdx]} {
            break
        }
        lassign $mIdx mStart mEnd
        set label [string range $body [lindex $labelIdx 0] [lindex $labelIdx 1]]

        # Find 'end block' and semicolon
        set level 0
        set endStart -1
        set semi -1
        for {set i $mEnd} {$i < $N} {incr i} {
            set ch [string index $body $i]
            if {$ch eq "("} {incr level}
            if {$ch eq ")"} {incr level -1}
            if {$level == 0 && [regexp -nocase -indices -start $i {\mend\M\s+\mblock\M} $body eIdx]} {
                set endStart [lindex $eIdx 0]
                set semi [string first ";" [string range $body $endStart $N]]
                if {$semi >= 0} { set semi [expr {$endStart + $semi}] }
                break
            }
        }
        if {$endStart < 0 || $semi < 0} { set idx [expr {$mEnd+1}]; continue }

        # Optional guard between 'block' and 'is'
        set header [string range $body $mEnd [expr {$endStart-1}]]
        set guard ""
        if {[regexp -nocase {^\s*(.*?)\s*\mis\M} $header -> g]} { set guard [string trim $g] }

        # Body between 'begin' and 'end block'
        set chunk [string range $body $mStart $semi]
        set bRel [regexp -indices -nocase {\mbegin\M} $chunk b2]
        set bodyTxt ""
        if {$bRel ne ""} {
            set bS [lindex $b2 1]
            set eRel [expr {$endStart - $mStart}]
            set bodyTxt [string trim [string range $chunk [expr {$bS+1}] [expr {$eRel-1}]]]
        }

        set line [::aurig::core::analyze::_index_to_line $body $mStart $n]
        lappend results [dict create label $label guard $guard body $bodyTxt line $line]
        set idx [expr {$semi+1}]
    }
    return $results
}
