-- Test comments in process headers and bodies
library ieee;
use ieee.std_logic_1164.all;

entity inline_process is
    port (
        clk : in std_logic;
        rst : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity inline_process;

architecture rtl of inline_process is
    signal reg : std_logic_vector(7 downto 0);
begin
    
    process -- comment after process
        ( -- comment after opening paren
        clk -- comment after clk
        , -- comment after comma
        rst -- comment after rst
        ) -- comment after closing paren
    begin -- comment after begin
        if -- comment after if
            rst -- comment after rst
            = -- comment after equals
            '1' -- comment after value
        then -- comment after then
            reg -- comment before assignment
            <= -- comment after assignment
            ( -- comment after opening paren
            others -- comment after others
            => -- comment after arrow
            '0' -- comment after value
            ) -- comment after closing paren
            ; -- comment after semicolon
        elsif -- comment after elsif
            rising_edge -- comment after rising_edge
            ( -- comment after opening paren
            clk -- comment inside function call
            ) -- comment after closing paren
        then -- comment after then
            reg <= data_in; -- end of line comment
        end -- comment after end
            if -- comment after if
            ; -- comment after semicolon
    end -- comment after end
        process -- comment after process
        ; -- comment after semicolon
    
    data_out <= reg;
    
end architecture rtl;
