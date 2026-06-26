-- Nested blocks
library ieee;
use ieee.std_logic_1164.all;

entity nested_blocks is
    port (
        clk : in std_logic;
        rst : in std_logic;
        data : inout std_logic
    );
end entity nested_blocks;

architecture rtl of nested_blocks is
begin
    outer_block: block
        signal outer_sig : std_logic;
    begin
        outer_sig <= data;
        
        inner_block: block
            signal inner_sig : std_logic;
        begin
            inner_sig <= outer_sig;
            
            process(clk, rst)
            begin
                if rst = '1' then
                    data <= '0';
                elsif rising_edge(clk) then
                    data <= inner_sig;
                end if;
            end process;
        end block inner_block;
    end block outer_block;
end architecture rtl;
