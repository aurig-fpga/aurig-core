-- Test generics with line breaks and irregular spacing
library ieee;
use ieee.std_logic_1164.all;

entity split_generics is
    generic (
        DATA_WIDTH : integer := 8;
        FIFO_DEPTH : positive := 16;
        USE_RESET : boolean := true
    );
    port (
        clk : in std_logic;
        data : out std_logic
    );
end entity split_generics;

architecture rtl of split_generics is
begin
    data <= '0';
end architecture rtl;
