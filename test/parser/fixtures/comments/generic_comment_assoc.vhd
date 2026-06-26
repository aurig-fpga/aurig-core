-- Test comment association with generics
library ieee;
use ieee.std_logic_1164.all;

entity generic_comment_assoc is
    generic (
        -- This comment precedes DATA_WIDTH
        DATA_WIDTH : integer := 8;
        
        -- This comment precedes FIFO_DEPTH after a blank line
        FIFO_DEPTH : positive := 16;
        
        USE_RESET : boolean := true; -- This is an end-of-line comment for USE_RESET
        
        -- Preceding comment for ADDR_WIDTH
        ADDR_WIDTH : integer := 10
    );
    port (
        clk : in std_logic
    );
end entity generic_comment_assoc;

architecture rtl of generic_comment_assoc is
begin
end architecture rtl;
