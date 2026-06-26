-- Testing unusual whitespace and formatting
library ieee;
use ieee.std_logic_1164.all;

entity whitespace_test is
    port (
        clk : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity whitespace_test;

architecture rtl of whitespace_test is
    signal reg : std_logic_vector(7 downto 0);
begin
    process(clk)
    begin
        if rising_edge(clk) then
            reg <= data_in;
        end if;
    end process;
    
    data_out <= reg;
    
end architecture rtl;
