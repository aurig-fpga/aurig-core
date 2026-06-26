# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.
#
# Standalone package index for aurig-core: a snapshot carve of tcl4fpga's lean
# shared core. declares ONLY aurig::core (renamed from upstream tcl4fpga::core;
# direct cutover, no compatibility alias).
package ifneeded aurig::core 0.1.0 [list source [file join $dir core.tcl]]
