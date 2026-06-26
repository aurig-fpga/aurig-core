-- Invalid: missing end statements
library ieee;
use ieee.std_logic_1164.all;

entity missing_end is
    port (
        clk : in std_logic
    );
-- Missing: end entity missing_end;

architecture rtl of missing_end is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- do something
        -- Missing: end if;
    -- Missing: end process;
-- Missing: end architecture rtl;
