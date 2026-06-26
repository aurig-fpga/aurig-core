-- SPDX-License-Identifier: Apache-2.0
-- Fixture: top-level entity resolved by name->file scanning.
library ieee;
use ieee.std_logic_1164.all;

entity top_entity is
  port (
    clk : in  std_logic;
    q   : out std_logic
  );
end entity top_entity;

architecture rtl of top_entity is
begin
  q <= clk;
end architecture rtl;
