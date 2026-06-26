-- Test strings containing comment markers and semicolons
library ieee;
use ieee.std_logic_1164.all;

entity strings_with_markers is
    port (
        clk : in std_logic
    );
end entity strings_with_markers;

architecture rtl of strings_with_markers is
    -- String with double dash
    constant MSG1 : string := "This has -- in it but it's not a comment";
    
    -- String with semicolon
    constant MSG2 : string := "This has ; in it";
    
    -- String with both
    constant MSG3 : string := "Both -- and ; are here";
    
    -- String with comment-like content
    constant MSG4 : string := "-- This looks like a comment but isn't";
    
    -- Multiple strings
    constant MSG5 : string := "First part --";
    constant MSG6 : string := "-- Second part";
    
    signal test : std_logic;
    
begin
    
    process
    begin
        -- Assert with string containing --
        assert false report "Error: -- not a comment" severity note;
        
        -- Assert with string containing ;
        assert test = '1' report "Value is; not what expected" severity warning;
        
        -- Report with mixed markers
        assert true report "Message: -- ; -- all in string" severity note;
        
        wait;
    end process;
    
end architecture rtl;
