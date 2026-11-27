namespace eval ::vhdl_index::lexer {
    # Negative tags are trivia, zero is EOF, 1 and 2 are identifiers.
    variable labels {eof identifier extended_identifier number string bit_string character invalid unsupported}
    variable words93 {
        abs access after alias all and architecture array assert attribute begin block body
        buffer bus case component configuration constant disconnect downto else elsif end
        entity exit file for function generate generic group guarded if impure in inertial
        inout is label library linkage literal loop map mod nand new next nor not null of on
        open or others out package port postponed procedure process pure range record register
        reject rem report return rol ror select severity shared signal sla sll sra srl
        subtype then to transport type unaffected units until use variable wait when while
        with xnor xor
    }
    variable baseSymbols {& ' ( ) * + , - . / : ; < = > | [ ]}
    variable extra02 {protected procedural reference}
    variable extra08 {
        assume assume_guarantee context cover default fairness force parameter property
        release restrict restrict_guarantee sequence strong vmode vprop vunit
    }
    variable sym93 {** := /= >= <= => <>}
    # Append edition tokens to preserve the existing immutable tape tags.
    variable sym08 {? @ << >> ?= ?/= ?< ?<= ?> ?>= ?? ^}
    variable symbols
    foreach word [concat $words93 $extra02 $extra08 $baseSymbols $sym93 $sym08] {
        dict set symbols $word [llength $labels]
        lappend labels $word
    }
    variable tables
    foreach edition {1993 2002 2008} {
        set table {}
        set lexemes [concat $words93 $baseSymbols $sym93]
        if {$edition == 2002} {lappend lexemes {*}$extra02}
        if {$edition >= 2008} {lappend lexemes protected {*}$extra08 {*}$sym08}
        foreach word $lexemes {
            dict set table $word [dict get $symbols $word]
        }
        set tables($edition) $table
    }
    unset word table lexemes edition
    variable white {\A[ \t\n\v\f\xa0]+}
    variable word {\A[A-Za-z_\xc0-\xd6\xd8-\xf6\xf8-\xff][A-Za-z_0-9\xc0-\xd6\xd8-\xf6\xf8-\xff]*}
    variable number {\A[0-9][0-9_]*(?:#[A-Za-z0-9_.]*#(?:[Ee][+-]?[0-9][0-9_]*)?|(?:\.[0-9][0-9_]*)?(?:[Ee][+-]?[0-9][0-9_]*)?)}
    variable numberAlternate {\A[0-9][0-9_]*:[A-Za-z0-9_.]+:(?:[Ee][+-]?[0-9][0-9_]*)?}
    variable bitPrefix {\A(?:[0-9][0-9_]*)?(?:[uUsS]?[bBoOxX]|[dD])(?=")}
    variable bitAlternate {\A[bBoOxX](?=%)}
    variable wordStart "\[A-Za-z_0-9\xc0-\xd6\xd8-\xf6\xf8-\xff]"
    variable graphic {^[\x20-\x7e\xa0-\xff]+$}
}

# Greedy doubled delimiters are resolved before committing a token. The
# bounded regex stops at a solitary delimiter, LF, or EOF.
proc ::vhdl_index::lexer::quoted {text start delimiter} {
    switch -- $delimiter {
        {"} {set pattern {\A"(?:""|[^"\n\v\f])*}}
        % {set pattern {\A%(?:%%|[^%"\n\v\f])*}}
        "\\" {set pattern {\A\\(?:\\\\|[^\\\n\v\f])*}}
    }
    regexp -indices -start $start -- $pattern $text extent
    set tail [expr {[lindex $extent 1] + 1}]
    if {[string index $text $tail] eq $delimiter} {
        return [list [expr {$tail + 1}] 1]
    }
    return [list $tail 0]
}

proc ::vhdl_index::lexer::diagnostic {code start end} {
    return [dict create code $code severity error span [list $start $end]]
}

proc ::vhdl_index::lexer::valid_number {spelling} {
    if {[string first # $spelling] < 0} {
        if {![regexp {^[0-9](?:_?[0-9])*(\.[0-9](?:_?[0-9])*)?(?:[eE]([+-]?)[0-9](?:_?[0-9])*)?$} \
            $spelling _ fraction sign]} {
            return 0
        }
        return [expr {$sign ne "-" || $fraction ne {}}]
    }
    if {![regexp {^([0-9](?:_?[0-9])*)#([[:xdigit:]](?:_?[[:xdigit:]])*(\.[[:xdigit:]](?:_?[[:xdigit:]])*)?)#(?:[eE]([+-]?)[0-9](?:_?[0-9])*)?$} \
        $spelling _ base digits fraction sign] || ($sign eq "-" && $fraction eq {})} {
        return 0
    }
    set base [string trimleft [string map {_ {}} $base] 0]
    if {[string length $base] > 2 || $base eq {} || $base < 2 || $base > 16} {
        return 0
    }
    foreach ch [split [string tolower [string map {_ {} . {}} $digits]] {}] {
        if {[string first $ch 0123456789abcdef] >= $base} {return 0}
    }
    return 1
}

proc ::vhdl_index::lexer::lex {snapshot edition limits} {
    variable tables
    variable symbols
    variable white
    variable word
    variable number
    variable bitPrefix
    variable bitAlternate
    variable numberAlternate
    variable graphic
    variable wordStart
    set table $tables($edition)
    set nameEnds {}
    foreach s {) ] >> all} {
        dict set nameEnds [dict get $symbols $s] 1
    }
    set attributeNames [list [dict get $symbols range] [dict get $symbols subtype]]
    set tick [dict get $symbols ']
    set text [dict get $snapshot text]
    set length [dict get $snapshot length]
    set limit [dict get $limits tokens]
    set kinds {}
    set starts {}
    set significant {}
    set diagnostics {}
    set whitespace " \t\n\v\f\xa0"
    set previous 0
    set penultimate 0
    set idx 0
    set previousEnd -1
    set previousWordish 0
    set alternateLines [regexp {[

]} $text]
    for {set i 0} {$i < $length} {set i $end} {
        set ch [string index $text $i]
        set kind 7
        set end [expr {$i + 1}]
        set problem {}
        set wordish 0
        # Escaped switch patterns disable compiled dispatch in Tcl 8.
        if {$idx >= $limit} {
            set end $length
            set kind 8
            set problem TOKEN_LIMIT
        } elseif {[string first $ch $whitespace] >= 0} {
            if {[string first [string index $text $end] $whitespace] >= 0} {
                regexp -indices -start $i -- $white $text match
                set end [expr {[lindex $match 1] + 1}]
            }
            set kind -1
        } elseif {$ch eq "\"" || $ch eq "\\" || ($edition < 2008 && $ch eq "%")} {
            lassign [quoted $text $i $ch] end closed
            set kind [expr {$ch eq "\\" ? 2 : 4}]
            set wordish [expr {$kind == 2}]
            set body [string range $text [expr {$i + 1}] [expr {$end - 2}]]
            if {!$closed} {
                set problem [expr {$kind == 4 ? "UNTERMINATED_STRING" : "UNTERMINATED_EXTENDED_IDENTIFIER"}]
            } elseif {($body ne {} && ![regexp -- $graphic $body]) || ($kind == 2 && $body eq {})} {
                set problem INVALID_QUOTED_GRAPHIC
            }
        } else {
            switch -- $ch {
                - {
                    if {[string index $text $end] eq "-"} {
                        if {$alternateLines} {
                            regexp -indices -start $i -- {\A--[^\n\v\f]*} $text match
                            set end [expr {[lindex $match 1] + 1}]
                        } else {
                            set end [string first "\n" $text $end]
                            if {$end < 0} {set end $length}
                        }
                        set kind -2
                    }
                }
                / {
                    if {$edition >= 2008 && [string index $text $end] eq "*"} {
                        set tail [string first "*/" $text [expr {$i + 2}]]
                        if {$tail < 0} {
                            set end $length
                            set problem UNTERMINATED_BLOCK_COMMENT
                        } else {
                            set end [expr {$tail + 2}]
                            set kind -3
                        }
                    }
                }
                ! {
                    if {$edition < 2008} {set kind [dict get $table |]}
                }
                ` {
                    if {$edition >= 2008} {
                        regexp -indices -start $i -- {\A[^\n\v\f]*} $text match
                        set end [expr {[lindex $match 1] + 1}]
                        set problem UNSUPPORTED_DIRECTIVE
                    }
                }
                ' {
                    set close [expr {$i + 2}]
                    if {[string index $text $close] eq "'" &&
                        [regexp -- $graphic [string index $text $end]] &&
                        $previous ni {1 2} && ![dict exists $nameEnds $previous] &&
                        !($penultimate == $tick && $previous in $attributeNames)} {
                        set end [expr {$close + 1}]
                        set kind 6
                    } else {
                        set kind $tick
                    }
                }
                default {
                    if {[string match $wordStart $ch]} {
                        if {$ch in {b B d D o O s S u U x X 0 1 2 3 4 5 6 7 8 9} &&
                            ([regexp -indices -start $i -- $bitPrefix $text match] ||
                             ($edition < 2008 && [regexp -indices -start $i -- $bitAlternate $text match]))} {
                            set quote [expr {[lindex $match 1] + 1}]
                            set prefix [string tolower [string range $text $i [expr {$quote - 1}]]]
                            set bracket [string index $text $quote]
                            regexp -indices -start [expr {$quote + 1}] -- {\A[^"%\n\v\f]*} $text match
                            if {$bracket eq "\""} {
                                regexp -indices -start [expr {$quote + 1}] -- {\A[^"\n\v\f]*} $text match
                            }
                            set boundary [expr {[lindex $match 1] + 1}]
                            set closed [expr {[string index $text $boundary] eq $bracket}]
                            set end [expr {$boundary + $closed}]
                            set kind 5
                            if {!$closed} {
                                set problem UNTERMINATED_BIT_STRING
                            } elseif {$edition < 2008 && $prefix ni {b o x}} {
                                set problem EDITION_BIT_STRING
                            } else {
                                set body [string range $text [expr {$quote + 1}] [expr {$end - 2}]]
                                set base [string index $prefix end]
                                set width [string trimright $prefix usboxd]
                                if {($body ne {} && ![regexp -- $graphic $body]) ||
                                    [string first "\"" $body] >= 0 ||
                                    [regexp {^_|__|_$} $body] ||
                                    ($width ne {} && ![regexp {^[0-9](?:_?[0-9])*$} $width]) ||
                                    ($base eq "d" && ![regexp {^[0-9][0-9_]*$} $body]) ||
                                    ($edition < 2008 && ![regexp -- [dict get {b {^[01_]*$} o {^[0-7_]*$} x {^[0-9a-fA-F_]*$}} $base] $body])} {
                                    set problem INVALID_BIT_STRING
                                }
                            }
                        } elseif {[string match {[0-9]} $ch]} {
                            regexp -indices -start $i -- $number $text match
                            set end [expr {[lindex $match 1] + 1}]
                            if {$edition < 2008 && [string index $text $end] eq ":" &&
                                [regexp -indices -start $i -- $numberAlternate $text match]} {
                                set end [expr {[lindex $match 1] + 1}]
                            }
                            set wordish 1
                            # A based literal missing its closing delimiter still owns
                            # its digit run. Leave the next separator available.
                            if {[string index $text $end] eq "#"} {
                                set problem INVALID_NUMBER
                                regexp -indices -start $end -- {\A#[A-Za-z0-9_.]*#?} $text match
                                set end [expr {[lindex $match 1] + 1}]
                            }
                            set kind 3
                            if {$end > $i + 1 &&
                                ![valid_number [string map {: #} [string range $text $i [expr {$end - 1}]]]]} {
                                set problem INVALID_NUMBER
                            }
                        } else {
                            regexp -indices -start $i -- $word $text match
                            set last [lindex $match 1]
                            set end [expr {$last + 1}]
                            set wordish 1
                            set spelling [string tolower [string range $text $i $last]]
                            if {[dict exists $table $spelling]} {
                                set kind [dict get $table $spelling]
                            } else {
                                set kind 1
                                if {$ch eq "_" || [string index $spelling end] eq "_" ||
                                    [string first "__" $spelling] >= 0} {
                                    set problem INVALID_IDENTIFIER
                                }
                            }
                        }
                    }
                }
            }
            if {$kind == 7 && $problem eq {}} {
                if {$ch in {* : / > < = ?}} {
                    set two [string range $text $i $end]
                    set three [string range $text $i [expr {$end + 1}]]
                    if {$ch eq "?" && [dict exists $table $three]} {
                        set kind [dict get $table $three]
                        incr end 2
                    } elseif {[string length $two] == 2 && [dict exists $table $two]} {
                        set kind [dict get $table $two]
                        incr end
                    }
                }
                if {$kind == 7} {
                    if {[dict exists $table $ch]} {
                        set kind [dict get $table $ch]
                    } else {
                        set problem INVALID_CHARACTER
                    }
                }
            }
        }
        if {$problem ne {}} {
            lappend diagnostics [diagnostic $problem $i $end]
            set kind [expr {$problem in {TOKEN_LIMIT EDITION_BIT_STRING UNSUPPORTED_DIRECTIVE} ? 8 : 7}]
        }
        if {$kind >= 0} {
            if {$wordish && $previousWordish && $i == $previousEnd} {
                lappend diagnostics [diagnostic MISSING_SEPARATOR $i $end]
            }
            set penultimate $previous
            set previous $kind
            set previousWordish $wordish
            set previousEnd $end
            lappend significant $idx
        }
        lappend kinds $kind
        lappend starts $i
        incr idx
    }
    lappend kinds 0
    lappend starts $length
    lappend significant $idx
    return [dict create kinds $kinds starts $starts significant $significant diagnostics $diagnostics]
}

proc ::vhdl_index::lexer::name {kind} {
    variable labels
    if {$kind >= 0} {return [lindex $labels $kind]}
    return [lindex {whitespace line_comment block_comment} [expr {-$kind - 1}]]
}

proc ::vhdl_index::lexer::token {tape i} {
    set starts [dict get $tape starts]
    set start [lindex $starts $i]
    set end [lindex $starts [expr {$i + 1}]]
    if {$end eq {}} {set end $start}
    return [list [name [lindex [dict get $tape kinds] $i]] $start $end]
}
