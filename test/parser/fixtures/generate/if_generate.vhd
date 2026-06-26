-- Test if-generate statement
library ieee;
use ieee.std_logic_1164.all;

entity if_generate is
    generic (
        USE_REGISTER : boolean := true
    );
    port (
        clk : in std_logic;
        din : in std_logic_vector(7 downto 0);
        dout : out std_logic_vector(7 downto 0)
    );
end entity if_generate;

architecture rtl of if_generate is
    signal temp : std_logic_vector(7 downto 0);
begin
    -- If-generate based on generic parameter
    gen_with_reg: if USE_REGISTER generate
        process(clk)
        begin
            if rising_edge(clk) then
                temp <= din;
            end if;
        end process;
        dout <= temp;
    end generate gen_with_reg;
    
    -- Else part of if-generate
    gen_no_reg: if not USE_REGISTER generate
        dout <= din;
    end generate gen_no_reg;
end architecture rtl;
