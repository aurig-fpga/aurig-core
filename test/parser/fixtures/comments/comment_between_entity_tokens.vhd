-- XFAIL: Parser cannot handle comment between "entity" and name
-- Expected: Should parse entity "test_entity" and ignore comment
-- Actual: Parser may fail to recognize entity or misparse name

library ieee;
use ieee.std_logic_1164.all;

entity -- This is a comment between entity keyword and name
  test_entity is
  port (
    input : in std_logic;
    output : out std_logic
  );
end entity test_entity;

architecture rtl of test_entity is
begin
  output <= input;
end architecture rtl;
