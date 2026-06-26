-- XFAIL: Parser cannot handle "generic" keyword split across lines
-- Expected: Should recognize generic declaration
-- Actual: Parser fails to parse generic list

library ieee;
use ieee.std_logic_1164.all;

entity generic_split is
  gene
ric (
    WIDTH : integer := 8
  );
  port (
    data_in : in std_logic_vector(WIDTH-1 downto 0);
    data_out : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity generic_split;

architecture rtl of generic_split is
begin
  data_out <= data_in;
end architecture rtl;
