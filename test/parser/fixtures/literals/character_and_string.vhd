-- Character literals in enumerations and strings with special content (tests empty entity)
library ieee;
use ieee.std_logic_1164.all;

entity character_literals is
end entity character_literals;

architecture rtl of character_literals is
    -- Enumeration with character literals
    type char_state is ('A', 'B', 'C', 'X', 'Z');
    signal state : char_state := 'A';
    
    -- Strings with embedded comment markers and semicolons
    constant MSG1 : string := "This has -- inside but not comment";
    constant MSG2 : string := "Contains ; semicolon";
    constant MSG3 : string := "Multiple -- markers -- here";
    constant MSG4 : string := "End with ;";
    constant MSG5 : string := "; starts with semicolon";
    
    -- String with quotes (escaped)
    constant MSG6 : string := "He said ""hello"" to me";
    constant MSG7 : string := """quoted""";
    
    -- Mixed special characters
    constant MSG8 : string := "Mix: -- and ; and ""quotes""";
    
    -- Bit string literals
    constant BIT_STR1 : bit_vector := B"1010";
    constant BIT_STR2 : bit_vector := O"377";
    constant BIT_STR3 : bit_vector := X"FF";
    
    -- Bit strings with underscores
    constant BIT_STR4 : bit_vector := B"1111_0000";
    constant BIT_STR5 : bit_vector := X"DEAD_BEEF";
    
    -- Character literal edge cases
    constant SPACE_CHAR : character := ' ';
    constant QUOTE_CHAR : character := ''';  -- single quote
    
begin
    process
    begin
        wait;
    end process;
end architecture rtl;
