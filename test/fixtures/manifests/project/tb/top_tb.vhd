-- SPDX-License-Identifier: Apache-2.0
-- Fixture: simulation testbench entity (file_sets.sim).
library ieee;
use ieee.std_logic_1164.all;

entity top_tb is
end entity top_tb;

architecture sim of top_tb is
  signal clk : std_logic := '0';
  signal q   : std_logic;
begin
  dut : entity work.top_entity
    port map (clk => clk, q => q);
  clk <= not clk after 5 ns;
end architecture sim;
