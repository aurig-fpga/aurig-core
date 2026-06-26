-- Mixed VHDL-93 and VHDL-2008 syntax
library ieee;
use ieee.std_logic_1164.all;

-- This context should be ignored/skipped
context ieee.ieee_std_context;

entity mixed_syntax is
    generic (
        WIDTH : integer := 8
    );
    port (
        clk : in std_logic;
        data : in std_logic_vector(WIDTH-1 downto 0);
        valid : out std_logic
    );
end entity mixed_syntax;

architecture rtl of mixed_syntax is
    signal internal : std_logic;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            valid <= internal;
        end if;
    end process;
end architecture rtl;
