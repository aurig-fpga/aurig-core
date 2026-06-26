-- Invalid: mismatched parentheses and brackets
library ieee;
use ieee.std_logic_1164.all;

entity mismatched_parens is
    port (
        data : in std_logic_vector(7 downto 0);  -- OK
        addr : in std_logic_vector(3 downto 0));  -- extra closing paren
        result : out std_logic_vector(15 downto 0  -- missing closing paren
    );
end entity mismatched_parens;

architecture rtl of mismatched_parens is
    signal temp : std_logic_vector((7 downto 0);  -- mismatched: (( vs );
begin
    process(data
    begin  -- missing closing paren on process sensitivity list
        temp <= data(7 downto 0;  -- missing closing paren
        result <= temp & data((3 downto 0);  -- extra opening paren
    end process;
end architecture rtl;
