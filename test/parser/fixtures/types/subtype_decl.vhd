-- Test subtype declarations with various constraints
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package subtype_pkg is
    -- Basic subtype with range constraint
    subtype byte is integer range 0 to 255;
    
    -- Subtype with downto range
    subtype nibble is integer range 15 downto 0;
    
    -- Subtype of std_logic_vector
    subtype data_word is std_logic_vector(31 downto 0);
    
    -- Subtype with constrained array
    subtype addr_bus is unsigned(15 downto 0);
    
    -- Subtype without constraint (just renaming)
    subtype my_logic is std_logic;
    
    -- Multiple subtypes with comments
    subtype small_int is integer range -128 to 127;  -- signed byte
    subtype control_bits is std_logic_vector(3 downto 0);  -- control
end package subtype_pkg;
