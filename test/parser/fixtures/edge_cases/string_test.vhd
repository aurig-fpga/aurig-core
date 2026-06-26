-- Testing strings with special characters
library ieee;
use ieee.std_logic_1164.all;

entity string_test is
    port (
        data : in std_logic
    );
end entity string_test;

architecture rtl of string_test is
    -- String with comment-like content
    constant MSG1 : string := "This string contains -- but it's not a comment";
    constant MSG2 : string := "Another string with ; semicolon";
    constant MSG3 : string := "Quotes: ""nested quotes"" here";
    constant MSG4 : string := "Special chars: @#$%^&*()";
    
    -- Report statements with strings
    signal test : std_logic;
    
begin
    
    process
    begin
        assert false report "Error message with -- comment chars" severity note;
        assert true report "Message: ""quoted text"" inside" severity note;
        wait;
    end process;
    
end architecture rtl;
