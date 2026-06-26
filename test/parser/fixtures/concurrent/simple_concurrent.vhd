-- Test simple concurrent signal assignment
library ieee;
use ieee.std_logic_1164.all;

entity simple_concurrent is
    port (
        a : in std_logic;
        b : in std_logic;
        c : in std_logic;
        result : out std_logic
    );
end entity simple_concurrent;

architecture rtl of simple_concurrent is
    signal temp1 : std_logic;
    signal temp2 : std_logic;
begin
    -- Simple concurrent assignments
    temp1 <= a and b;
    temp2 <= temp1 or c;
    result <= temp2;
    
    -- Direct assignment
    result <= (a and b) or c;
end architecture rtl;
