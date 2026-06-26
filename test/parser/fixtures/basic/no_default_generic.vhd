-- Entity with generic but no default value
library ieee;
use ieee.std_logic_1164.all;

entity no_default_generic is
    generic (
        WIDTH : integer;
        DEPTH : positive
    );
    port (
        data : in std_logic_vector(WIDTH-1 downto 0)
    );
end entity no_default_generic;

architecture rtl of no_default_generic is
begin
end architecture rtl;
