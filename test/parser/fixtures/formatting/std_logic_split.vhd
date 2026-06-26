-- XFAIL: Parser cannot handle type names split across lines
-- Expected: Should recognize "std_logic" as the type
-- Actual: Parser fails to parse type correctly

library ieee;
use ieee.std_logic_1164.all;

entity type_split is
  port (
    clk : in std_
logic;
    data : out std_
logic
  );
end entity type_split;

architecture rtl of type_split is
begin
  data <= clk;
end architecture rtl;
