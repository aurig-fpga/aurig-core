-- Entity with minimal port
library ieee;
use ieee.std_logic_1164.all;

entity empty_entity is
    port (
        dummy : in std_logic
    );
end entity empty_entity;

architecture rtl of empty_entity is
    signal internal : std_logic;
begin
    internal <= dummy;
end architecture rtl;
