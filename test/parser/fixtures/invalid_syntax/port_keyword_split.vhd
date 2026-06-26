-- INVALID_SYNTAX: VHDL keywords cannot be split across lines
-- This is NOT a parser limitation - this is invalid VHDL syntax
-- Expected: Parser should reject this with an error
-- Note: Splitting "port" as "po\nrt" violates VHDL language rules

library ieee;
use ieee.std_logic_1164.all;

entity port_split is
  po
rt (
    clk : in std_logic;
    data : out std_logic
  );
end entity port_split;

architecture rtl of port_split is
begin
  data <= clk;
end architecture rtl;
