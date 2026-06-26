-- Test that blank lines prevent comment association
library ieee;
use ieee.std_logic_1164.all;

-- This comment is separated from the entity by a blank line

entity no_assoc_blank_line is
    generic (
        -- This comment is for WIDTH
        WIDTH : integer := 8;

        -- This comment is separated by a blank line and should NOT associate with DEPTH
        
        DEPTH : integer := 16
    );
    port (
        -- Comment for clk
        clk : in std_logic;

        -- Comment separated by blank line, should NOT associate with data
        
        data : in std_logic_vector(WIDTH-1 downto 0)
    );
end entity no_assoc_blank_line;

architecture rtl of no_assoc_blank_line is

    -- Comment separated by blank line from signal
    
    signal reg : std_logic_vector(WIDTH-1 downto 0);
    
begin
end architecture rtl;
