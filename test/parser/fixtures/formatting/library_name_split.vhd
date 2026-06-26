-- XFAIL: Parser cannot handle library name split across lines
-- Expected: Should recognize "ieee" as library name
-- Actual: Parser fails to parse library declaration

lib
rary ie
ee;
use ieee.std_logic_1164.all;

entity lib_split is
  port (
    input : in std_logic;
    output : out std_logic
  );
end entity lib_split;

architecture rtl of lib_split is
begin
  output <= input;
end architecture rtl;
