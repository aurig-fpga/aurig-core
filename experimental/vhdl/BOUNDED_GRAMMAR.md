<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# P-A bounded grammar profile

| Entry | Extracted syntax |
| --- | --- |
| Name | Designators, selection, dereference, parenthesized index and slice candidates, attribute names and attribute parameters, signatures before attributes, and VHDL-2008 external paths |
| Expression | Literal and name primaries, grouping, operators at the VHDL grammar levels, calls and actuals, conversions, qualified expressions, aggregates and allocators |
| Discrete range | A simple-expression range with explicit direction, a range attribute, or a discrete subtype spelling |

The caller passes a snapshot and tape from the same read and edition, along with an inclusive first and exclusive last significant-token ordinal. The EOF ordinal is a legal exclusive endpoint. The optional source-span adapter maps normalized character offsets to significant ordinals and rejects a boundary inside a significant token. Complete results cover every significant token in the interval. Exact token and node spans use normalized, half-open source offsets.

The engine uses the existing lexer and cursor. Its depth limit is 32 active nested groups and its node budget is 100,000 compact rows per interval. Both limits can be lowered by the caller. The lexer has a separate token limit. Flat operator and suffix chains consume row budget without proportional recursion.

The `parsed` and `ambiguous` results publish a root. The `unsupported`, `malformed` and `unavailable` results publish diagnostics and the unresolved interval. A simple name used as a single parenthesized argument may denote an index, a discrete subtype in a slice, an actual, or a conversion operand. Candidate flags record these syntactic paths without binding names. Named actuals and explicit range directions narrow the candidate set. Array and record type legality, visibility, overloads, staticness and values require semantic analysis.

VHDL-2008 adds matching operators, the condition operator, logical reduction operators and external names. The parser supports standalone reductions and reductions grouped within larger expressions. Combined unparenthesized reduction forms are `unsupported` pending reconciliation of IEEE 1076-2008 clause 9.1 and its note. Record element constraints in subtype indications, external element resolution and PSL expression extensions also remain outside the validated profile. VHDL-2019 is unsupported.

This interface is revision-specific. The payload module integrates the same expression and discrete-range entries with proved structural carriers. It checks snapshot and edition provenance before narrowing a retained source span to significant tokens. An ordinary structural analysis has no payload registry or arena. Contextual adapters and semantic resolution remain separate work. [Payload operations](README.md#bounded-name-and-expression-experiment)
