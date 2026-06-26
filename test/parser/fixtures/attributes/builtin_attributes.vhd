-- Test built-in VHDL attributes usage
library ieee;
use ieee.std_logic_1164.all;

entity builtin_attributes is
    port (
        data : in std_logic_vector(7 downto 0);
        index : in integer
    );
end entity builtin_attributes;

architecture rtl of builtin_attributes is
    signal bit_val : std_logic;
    signal left_idx : integer;
    signal right_idx : integer;
    signal length_val : integer;
    signal range_val : integer;
begin
    -- Using built-in attributes
    left_idx <= data'left;
    right_idx <= data'right;
    length_val <= data'length;
    range_val <= data'range;
    
    -- Event attribute
    bit_val <= '1' when data'event else '0';
    
    -- Array attribute with index
    bit_val <= data(index);
end architecture rtl;
