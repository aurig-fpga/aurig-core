-- Simple component instantiation
library ieee;
use ieee.std_logic_1164.all;

entity simple_generate is
    port (
        clk : in std_logic;
        data_in : in std_logic;
        data_out : out std_logic
    );
end entity simple_generate;

architecture rtl of simple_generate is
    signal reg : std_logic;
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            reg <= data_in;
        end if;
    end process;
    
    data_out <= reg;
    
end architecture rtl;
