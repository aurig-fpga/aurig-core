-- Entity with no generics and no ports (valid VHDL, common in testbenches)
library ieee;
use ieee.std_logic_1164.all;

entity empty_entity is
end entity empty_entity;

architecture rtl of empty_entity is
  signal internal : std_logic := '0';
begin
  internal <= '1';
end architecture rtl;
