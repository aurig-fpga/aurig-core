-- Test entity and ports with line breaks in unexpected places
library ieee;
use ieee.std_logic_1164.all;

entity split_entity_port
    is
    port (
        clk
        :
        in
        std_logic;
        rst
        :
        in
        std_logic;
        data_in
        :
        in
        std_logic_vector(7 downto 0);
        data_out
        :
        out
        std_logic_vector(7 downto 0)
    );
end entity split_entity_port;

architecture rtl of split_entity_port is
begin
    data_out <= data_in;
end architecture rtl;
