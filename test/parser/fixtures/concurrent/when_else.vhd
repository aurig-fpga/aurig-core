-- Test conditional signal assignment (when/else)
library ieee;
use ieee.std_logic_1164.all;

entity when_else is
    port (
        sel : in std_logic_vector(1 downto 0);
        a : in std_logic_vector(7 downto 0);
        b : in std_logic_vector(7 downto 0);
        c : in std_logic_vector(7 downto 0);
        d : in std_logic_vector(7 downto 0);
        output : out std_logic_vector(7 downto 0)
    );
end entity when_else;

architecture rtl of when_else is
begin
    -- Conditional signal assignment with when/else
    output <= a when sel = "00" else
              b when sel = "01" else
              c when sel = "10" else
              d;
              
    -- Another example with conditions
    output <= x"FF" when sel = "11" else
              x"00" when sel = "00" else
              a;
end architecture rtl;
