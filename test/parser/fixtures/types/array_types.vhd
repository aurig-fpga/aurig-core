-- Test array type declarations including array-of-array
library ieee;
use ieee.std_logic_1164.all;

package array_pkg is
    -- Simple 1D array
    type byte_array is array (0 to 7) of std_logic_vector(7 downto 0);
    
    -- Array with natural range
    type int_array is array (natural range <>) of integer;
    
    -- Constrained array with downto
    type mem_block is array (15 downto 0) of std_logic_vector(31 downto 0);
    
    -- Array of array (2D)
    type matrix_4x4 is array (0 to 3) of std_logic_vector(31 downto 0);
    
    -- Unconstrained array
    type data_bus is array (natural range <>) of std_logic;
    
    -- Array with comments and split formatting
    type register_file is array (
        0 to 31  -- 32 registers
    ) of std_logic_vector(63 downto 0);  -- 64-bit each
    
    -- Array of records
    type pixel is record
        r : std_logic_vector(7 downto 0);
        g : std_logic_vector(7 downto 0);
        b : std_logic_vector(7 downto 0);
    end record pixel;
    
    type image_row is array (0 to 639) of pixel;
end package array_pkg;
