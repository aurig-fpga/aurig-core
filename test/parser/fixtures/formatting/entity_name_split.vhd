-- XFAIL: Parser cannot handle entity name split across lines
-- Expected: Should parse entity name as "my_entity"
-- Actual: Parser fails to recognize entity declaration

library ieee;
use ieee.std_logic_1164.all;

entity my
_entity is
  port (
    clk : in std_logic;
    rst : in std_logic;
    data_out : out std_logic
  );
end entity my_entity;

architecture rtl of my_entity is
begin
  process(clk, rst)
  begin
    if rst = '1' then
      data_out <= '0';
    elsif rising_edge(clk) then
      data_out <= '1';
    end if;
  end process;
end architecture rtl;
