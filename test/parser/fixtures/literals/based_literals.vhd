-- Based literals: binary, octal, hex (tests empty entity with no ports/generics)
library ieee;
use ieee.std_logic_1164.all;

entity based_literals is
end entity based_literals;

architecture rtl of based_literals is
    -- Binary based literals
    constant BIN_VAL1 : integer := 2#1010#;
    constant BIN_VAL2 : integer := 2#1111_0000#;
    
    -- Octal based literals
    constant OCT_VAL1 : integer := 8#377#;
    constant OCT_VAL2 : integer := 8#177_777#;
    
    -- Hexadecimal based literals
    constant HEX_VAL1 : integer := 16#FF#;
    constant HEX_VAL2 : integer := 16#DEAD_BEEF#;
    constant HEX_VAL3 : integer := 16#ff#;  -- lowercase
    constant HEX_VAL4 : integer := 16#FfAa#; -- mixed case
    
    -- With exponents
    constant HEX_EXP : integer := 16#F#E2;  -- 15 * 16^2
    constant BIN_EXP : integer := 2#1010#E3; -- 10 * 2^3
    
    -- Edge case: base 16 with all hex digits
    constant ALL_DIGITS : integer := 16#0123456789ABCDEF#;
begin
end architecture rtl;
