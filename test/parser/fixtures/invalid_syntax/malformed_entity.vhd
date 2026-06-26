-- Invalid: malformed entity declaration
library ieee;
use ieee.std_logic_1164.all;

entity  -- missing entity name
    port (
        clk : in std_logic
    );
end entity;

-- Invalid: entity with duplicate port names
entity duplicate_ports is
    port (
        data : in std_logic;
        data : out std_logic  -- duplicate name
    );
end entity duplicate_ports;

architecture rtl of duplicate_ports is
begin
end architecture rtl;
