-- Test multiple attributes on same object
library ieee;
use ieee.std_logic_1164.all;

entity multiple_attributes is
    port (
        critical_sig : in std_logic_vector(15 downto 0)
    );
end entity multiple_attributes;

architecture rtl of multiple_attributes is
    -- Declare multiple attributes
    attribute KEEP : string;
    attribute DONT_TOUCH : string;
    attribute MAX_FANOUT : integer;
    attribute PRIORITY : string;
    attribute TIMING : time;
    
    signal important : std_logic;
    
    -- Multiple attributes on same signal
    attribute KEEP of important : signal is "TRUE";
    attribute DONT_TOUCH of important : signal is "YES";
    attribute MAX_FANOUT of important : signal is 10;
    attribute PRIORITY of important : signal is "HIGH";
    attribute TIMING of important : signal is 5 ns;
    
    -- Multiple attributes on port
    attribute KEEP of critical_sig : signal is "TRUE";
    attribute MAX_FANOUT of critical_sig : signal is 20;
begin
    important <= critical_sig(0);
end architecture rtl;
