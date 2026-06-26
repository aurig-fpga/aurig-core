-- XFAIL: Parser mishandles VHDL keywords in comments
-- Expected: Comments with keywords should be treated as plain text
-- Actual: Parser may incorrectly try to parse keywords in comments

library ieee;
use ieee.std_logic_1164.all;

entity comment_keywords is
  port (
    -- entity port signal end architecture if then else
    -- These keywords in comments should be ignored: type record array
    input : in std_logic;
    output : out std_logic
  );
end entity comment_keywords;

architecture rtl of comment_keywords is
  -- signal internal : std_logic;
  -- This commented-out signal declaration should NOT create a signal
begin
  output <= input;
end architecture rtl;
