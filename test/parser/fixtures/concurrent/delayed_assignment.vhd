-- Test concurrent assignments with transport and inertial delay
library ieee;
use ieee.std_logic_1164.all;

entity delayed_assignment is
    port (
        input : in std_logic;
        transport_out : out std_logic;
        inertial_out : out std_logic
    );
end entity delayed_assignment;

architecture rtl of delayed_assignment is
begin
    -- Concurrent assignment with transport delay
    transport_out <= transport input after 10 ns;
    
    -- Concurrent assignment with inertial delay (default)
    inertial_out <= input after 5 ns;
    
    -- Explicit inertial delay with reject
    inertial_out <= reject 2 ns inertial input after 5 ns;
end architecture rtl;
