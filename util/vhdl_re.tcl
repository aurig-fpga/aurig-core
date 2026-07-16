# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# this file contains the regexp (TCL) for VHDL parsing

namespace eval ::aurig::core::util::re {
  # regexps shall be enclosed between (), as the whole group shall be
  # used to be removed from the file buffer, when parsed
  # file to be parse has leading whitespaces removed so we have to search from beginning of the line

  # common variables
  # identifier
  variable re_id {[a-zA-Z]+[a-zA-Z0-9_]*}

  variable re_id_ext {[a-zA-Z0-9_\'\"\s\+\*-\/]*}

  ###############################################################################
  # for each regexp the returning blocks are described

  # library declaration
  # description: non greedy library keyword up to ";"
  # 1. library name
  variable re_library_decl {^(library[\s\n]+?([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*;)}

  # library use
  # description: parses the library use — use with -nocase flag
  # 1. library name
  # 2. package name (optional)
  # 3. selector (e.g. "all" or type name)
  variable re_library_use {^\s*use[\s\n]+([a-zA-Z]\w*)[\s\n]*\.[\s\n]*(?:([a-zA-Z]\w*)[\s\n]*\.[\s\n]*)?(all|[a-zA-Z]\w*(?:[\s\n]*,[\s\n]*[a-zA-Z]\w*)*)[\s\n]*;}

  # package declaration
  # description: lazy! from package to end. Matches from "package <name> is" to the closing "end" statement.
  # The closing can be: "end package;", "end package <name>;", "end <name>;", or just "end;"
  # Group 1: Full match
  # Group 2: package name
  # Group 3: package declarative part
  variable re_package_decl {^(package[\s\n]+?([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*is[\s\n]+(.*?)(?:end[\s\n]+package(?:[\s\n]+\2)?|end[\s\n]+\2|end)[\s\n]*;)}

  # package body
  # description: from package body to end. the assumption is that the final end of the file
  # is the one associated with the package body. that's why the greedy regexp
  # this is usually true when package declaration and package body are in the same ifle and the
  # package body comes after the package declaration
  # 1. package name
  # 2. package body part
  variable re_package_body {^(package[\s\n]+body[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*is[\s\n]+(.*)(?:end[\s\n]+package[\s\n]+body|end[\s\n]+package[\s\n]+body[\s\n]+[a-zA-Z]+[a-zA-Z0-9_]*|end[\s\n]*;))}

  # entity
  # description: from entity to the first end statement, the lazy helps here
  # 1. entity name
  # 2. entity generic and port section
  variable re_entity {^(entity[\s\n]+?([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*is[\s\n]+(.*)(?:end[\s\n]+entity|end[\s\n]+entity[\s\n]+[a-zA-Z]+[a-zA-Z0-9_]*|end[\s\n]+[a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*;)}

  # architecture
  # description: from architcture to the end statement, greedy as we are assuming the last
  # end is associated with architecture in a classis entity-architcture file structure
  # 1. architecture name
  # 2. entity name associated
  # 3. architcture declarative part
  # 4. architecture body
  variable re_architecture {^(architecture[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]+of[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]+is[\s\n]+(.*)begin[\s\n]+(.*)[\s\n]+(end[\s\n]+architecture|end[\s\n]+architecture[\s\n]+[a-zA-Z]+[a-zA-Z0-9_]*|end[\s\n]+[a-zA-Z]+[a-zA-Z0-9_]*|end)[\s\n]*;)}

  # port list
  # description: extract port declaration from an entity item
  # returns:
  # 1. port list, excluding port keyword and parentheses
  variable re_port_list {[\s\n]*port[\s\n]*\([\s\n]*(.*)(?:\);[\s\n]*end[\s\n]*;|\);[\s\n]*end[\s\n]+[a-zA-Z0-9_]+;|\);[\s\n]*end[\s\n]+[a-zA-Z]+[\s\n]+[a-zA-Z]+[a-zA-Z0-9_]*;)}

  # port item
  # description: extract port item from a port list
  # returns:
  # 1. port name
  # 2. port mode (in, out, inout)
  # 3. port type (std_logic, std_logic_vector, etc.)
  # 4. default value (optional)
  variable re_port_item {([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]*:[\s\n]*(in|out|inout|buffer)[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*|[a-zA-Z]+[a-zA-Z0-9_]*\([a-zA-Z0-9_\'\" \+\*-\/]*\))[\s\n]*(;|:=[\s\n]*([a-zA-Z0-9_'" =><\+\*-\/\(\)]*))}

  # generic list
  # description: extract generic declaration from an entity item
  # returns:
  # 1. generic list, excluding generic keyword and parentheses
  variable re_generic_list {[\s\n]*?generic[\s\n]*\((.*)(?:\)[\s\n]*;[\s\n]*port|\)[\s\n]*;[\s\n]*end)}

  ###############################################################################
  # Additional patterns used across the analysis modules

  # library reference (scanning merged/multi-line context)
  # description: library keyword followed by identifier and semicolon — use with -nocase flag
  # 1. library name
  variable re_library_ref {library[\s\n]+(\w+)[\s\n]*;}

  # entity instantiation (direct entity keyword form)
  # description: label : entity lib.name — use with -nocase flag
  # 1. instance label
  # 2. fully-qualified entity name (e.g. demo_util_lib.demo_util_ram)
  variable re_entity_inst {(\w+)[\s\n]*:[\s\n]*entity[\s\n]+([\w.]+)}

  # component declaration
  # description: component keyword followed by component name — use with -nocase flag
  # 1. component name
  variable re_component_decl {^\s*component[\s\n]+([\w]+)}

  # component instantiation (port map form, no entity/component keyword)
  # description: label : name port map — use with -nocase flag
  # 1. component/entity name
  variable re_component_inst {^\s*[a-zA-Z0-9_]+[\s\n]*:[\s\n]*([a-zA-Z0-9_]+)[\s\n]+port[\s\n]+map}

  # type declaration (single-line form)
  # description: type <name> is <definition>; — use with -nocase flag
  # 1. type identifier
  # 2. type definition
  variable re_type_decl {[\s\n]*type[\s\n]+([a-zA-Z]+[a-zA-Z0-9_]*)[\s\n]+is[\s\n]+([a-zA-Z]+.*)[\s\n]*;}

  # entity declaration header (single-line, for quick name extraction)
  # description: entity <name> is — use with -nocase flag
  # 1. entity name
  variable re_entity_header {^\s*entity[\s\n]+(\w+)[\s\n]+is}

  # component instantiation with component keyword
  # description: label : component <name> generic/port map — use with -nocase flag
  # 1. component name
  variable re_component_inst_kw {\w+[\s\n]*:[\s\n]*component[\s\n]+(\w+)[\s\n]+(?:generic|port)[\s\n]+map}

  # entity instantiation with library qualification
  # description: label : entity lib.<name> — use with -nocase flag
  # 1. entity name (without library prefix)
  variable re_entity_inst_lib {\w+[\s\n]*:[\s\n]*entity[\s\n]+\w+\.(\w+)}

  # direct instantiation (no entity/component keyword)
  # description: label : name generic/port map — use with -nocase flag
  # 1. instance label
  # 2. component/entity name
  variable re_direct_inst {(\w+)[\s\n]*:[\s\n]*(\w+)[\s\n]+(?:generic[\s\n]+map|port[\s\n]+map)}

  # function declaration
  # description: function ... return ... is — use with -nocase flag
  variable re_function_decl {function[\s\n]+.*?return[\s\n]+.*?is}

  # generic map clause opener
  # description: generic map ( — use with -nocase flag
  # Locates the start of a `generic map (...)` association list on an
  # instantiation statement. The capturing parenthesis itself is the
  # last literal; balanced-paren scanning typically takes over from the
  # match end. No anchors so callers may use `\m`/`^\s*` when needed.
  variable re_generic_map {generic\s+map\s*\(}

  # port map clause opener
  # description: port map ( — use with -nocase flag
  # Mirrors `re_generic_map` for port maps; used both to confirm an
  # instantiation and to slice the association list.
  variable re_port_map {port\s+map\s*\(}

  # generic clause opener (declaration form, not map)
  # description: generic ( — use with -nocase flag
  # Matches the opening of a `generic (...)` declaration on an entity
  # or component. Bare form without anchors; callers concatenate
  # `^\s*` or `\m` when stricter positioning is needed.
  variable re_generic_decl_open {generic\s*\(}

  # architecture header (loose form)
  # description: architecture <name> of <entity> is — use with -nocase flag
  # Loose `\w+` form used for whole-line / whole-buffer detection of an
  # architecture header (no name capture, no `\s|$` tail). The strict,
  # capture-bearing form lives inline in `analyze/vhdlscan.tcl`'s lint
  # entity/architecture stack tracker because that callsite needs the
  # `[A-Za-z][A-Za-z0-9_]*` identifier class and `is(\s|$)` tail.
  variable re_architecture_header {architecture\s+\w+\s+of\s+\w+\s+is}

  # `generate` keyword (boundary-anchored)
  # description: `\mgenerate\M` — use with -nocase flag
  # Word-boundary keyword form used to locate the `generate` token in
  # both the parser's generate-statement walker and the freeze validator's
  # forbidden-token check. The `\m`/`\M` boundaries prevent false positives
  # on identifiers like `degenerate` or `regenerate_clk`.
  variable re_generate_kw {\mgenerate\M}

  # `end generate` keyword pair (boundary-anchored)
  # description: `\mend\s+generate\M` — use with -nocase flag
  # Word-boundary keyword pair used to locate the end of a generate
  # statement. The `\s+` between tokens accepts any whitespace
  # (space/tab/newline) and implicitly enforces the boundary between
  # `end` and `generate`, so the longer `\mend\M\s+\mgenerate\M` form
  # is byte-different but semantically equivalent on any real subject
  # (any character matched by `\s+` is already a word boundary on both
  # sides). The shorter form is the centralized one; the equivalence
  # is pinned by `test/test_vhdl_re_centralization.tcl`.
  variable re_end_generate_kw {\mend\s+generate\M}

}
