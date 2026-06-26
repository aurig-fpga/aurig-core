-- Multiple architectures for the same entity
library ieee;
use ieee.std_logic_1164.all;

entity multi_arch is
    port (
        a : in std_logic;
        b : in std_logic;
        y : out std_logic
    );
end entity multi_arch;

-- First architecture - AND gate
architecture and_gate of multi_arch is
begin
    y <= a and b;
end architecture and_gate;

-- Second architecture - OR gate
architecture or_gate of multi_arch is
begin
    y <= a or b;
end architecture or_gate;

-- Third architecture - XOR gate
architecture xor_gate of multi_arch is
begin
    y <= a xor b;
end architecture xor_gate;
