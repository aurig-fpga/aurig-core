-- Test selected signal assignment (with/select)
library ieee;
use ieee.std_logic_1164.all;

entity with_select is
    port (
        sel : in std_logic_vector(1 downto 0);
        a : in std_logic_vector(7 downto 0);
        b : in std_logic_vector(7 downto 0);
        c : in std_logic_vector(7 downto 0);
        d : in std_logic_vector(7 downto 0);
        output : out std_logic_vector(7 downto 0)
    );
end entity with_select;

architecture rtl of with_select is
begin
    -- Selected signal assignment with with/select
    with sel select output <=
        a when "00",
        b when "01",
        c when "10",
        d when "11",
        x"00" when others;
        
    -- Another example with expressions
    with sel select output <=
        a when "00",
        b when "01",
        (others => '0') when others;
end architecture rtl;
