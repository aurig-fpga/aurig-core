-- Test comments inside signal and constant declarations
library ieee;
use ieee.std_logic_1164.all;

entity inline_signal_constant is
    port (
        clk : in std_logic
    );
end entity inline_signal_constant;

architecture rtl of inline_signal_constant is
    
    constant -- comment between constant and name
        INIT_VALUE -- comment between name and colon
        : -- comment between colon and type
        std_logic_vector -- comment between type and range
        ( -- comment after opening paren
        7 -- comment between bounds
        downto -- comment after downto
        0 -- comment before closing paren
        ) -- comment between paren and assign
        := -- comment between assign and value
        x"00" -- comment after value
        ; -- comment after semicolon
    
    signal -- comment between signal and name
        data_reg -- comment between name and colon
        : -- comment between colon and type
        std_logic_vector -- comment between type and range
        ( -- comment after opening paren
        7 -- comment between bounds
        downto -- comment after downto
        0 -- comment before closing paren
        ) -- comment after paren
        ; -- comment after semicolon
    
    signal -- comment after signal
        counter : integer range 0 to 255; -- end of line comment
    
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            data_reg <= INIT_VALUE;
        end if;
    end process;
    
end architecture rtl;
