-- Time literals and physical types (tests empty entity)
library ieee;
use ieee.std_logic_1164.all;

entity time_literals is
end entity time_literals;

architecture rtl of time_literals is
    -- Standard time literals
    constant T1 : time := 10 ns;
    constant T2 : time := 1 us;
    constant T3 : time := 50 ms;
    constant T4 : time := 2 sec;
    
    -- Time with underscores
    constant T5 : time := 1_000 ns;
    constant T6 : time := 100_000_000 ps;
    
    -- Fractional time
    constant T7 : time := 1.5 ns;
    constant T8 : time := 0.1 us;
    
    -- Edge cases
    constant T9 : time := 1 fs;  -- femtoseconds
    constant T10 : time := 1 hr; -- hours
    
    signal delayed_sig : std_logic;
begin
    -- Use in signal assignment with delay
    delayed_sig <= '1' after 10 ns, '0' after 20 ns;
end architecture rtl;
