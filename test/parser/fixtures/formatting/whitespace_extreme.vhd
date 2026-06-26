-- Test signal and constant declarations with extreme whitespace
library ieee;
use ieee.std_logic_1164.all;

entity whitespace_extreme is
    port (
        clk : in std_logic;
        data : in std_logic_vector(7 downto 0)
    );
end entity whitespace_extreme;

architecture rtl of whitespace_extreme is
    
    constant    INIT_VALUE    :    std_logic_vector    (    7    downto    0    )    :=    x"00"    ;
    
    constant
        MAX_COUNT
        :
        integer
        :=
        255
        ;
    
    signal      data_reg      :      std_logic_vector      (      7      downto      0      )      ;
    
    signal
        counter
        :
        integer
        range
        0
        to
        MAX_COUNT
        ;
    
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            data_reg     <=     data     ;
            counter   <=   counter   +   1   ;
        end if;
    end process;
    
end architecture rtl;
