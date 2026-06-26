-- Invalid: unterminated string literal
library ieee;
use ieee.std_logic_1164.all;

entity unterminated_string is
end entity unterminated_string;

architecture rtl of unterminated_string is
    -- This string is not terminated properly
    constant MSG : string := "This string never ends
begin
end architecture rtl;
