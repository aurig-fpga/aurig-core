-- Test comments inside strings must NOT be treated as comments
library ieee;
use ieee.std_logic_1164.all;

entity string_not_comment is
    port (
        clk : in std_logic
    );
end entity string_not_comment;

architecture rtl of string_not_comment is
    
    -- This is a real comment
    constant MSG1 : string := "This -- looks like a comment but isn't";
    
    constant MSG2 : string := "No comment here"; -- But this IS a comment
    
    -- Real comment before MSG3
    constant MSG3 : string := "String with -- inside" := "default -- value";
    
    signal test : std_logic; -- Real comment
    
begin
    
    process
    begin
        -- Real comment in process
        assert false report "Message with -- inside" severity note;
        wait;
    end process;
    
end architecture rtl;
