-- Test for-generate statement
library ieee;
use ieee.std_logic_1164.all;

entity for_generate is
    port (
        clk : in std_logic;
        din : in std_logic_vector(7 downto 0);
        dout : out std_logic_vector(7 downto 0)
    );
end entity for_generate;

architecture rtl of for_generate is
    signal stage : std_logic_vector(7 downto 0);
begin
    -- Simple for-generate creating multiple instances
    gen_regs: for i in 0 to 7 generate
        process(clk)
        begin
            if rising_edge(clk) then
                stage(i) <= din(i);
            end if;
        end process;
    end generate gen_regs;
    
    dout <= stage;
end architecture rtl;
