---
name: Bug report
about: Report incorrect or unexpected behavior in the parser, utilities, or schema
title: ''
labels: bug
assignees: ''
---

## Description

A clear description of the bug.

## Input snippet

The smallest VHDL source or YAML/INI manifest that reproduces the issue:

```vhdl
-- your VHDL here
```

## Tcl reproduction

The smallest script that reproduces it (which `::aurig::core::*` call, and how):

```tcl
package require aurig::core
set ast [::aurig::core::analyze::vhdlscan -in design.vhd]
# ...
```

## Expected behavior

What you expected aurig-core to return or do.

## Actual behavior

What actually happened (paste the parse dict, result, or error output).

## Versions

- aurig-core: <!-- git commit or tag -->
- Tcl: <!-- output of `echo 'puts [info patchlevel]' | tclsh` -->
- tcllib: <!-- only if the manifest/schema path is involved -->

## OS / environment

<!-- e.g. Ubuntu 24.04, Windows 11 + ActiveTcl 8.6 -->
