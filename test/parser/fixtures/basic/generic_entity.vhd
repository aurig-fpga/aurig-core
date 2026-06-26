-- Entity with generics
library ieee;
use ieee.std_logic_1164.all;

entity generic_entity is
    generic (
        DATA_WIDTH : integer := 8;
        FIFO_DEPTH : positive := 16;
        USE_RESET : boolean := true
    );
    port (
        clk : in std_logic;
        rst : in std_logic;
        input : in std_logic_vector(DATA_WIDTH-1 downto 0);
        output : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity generic_entity;

architecture rtl of generic_entity is
begin
    output <= input;
end architecture rtl;
