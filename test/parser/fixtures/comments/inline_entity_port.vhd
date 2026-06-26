-- Test comments between entity and port tokens
library ieee;
use ieee.std_logic_1164.all;

-- Test comments between entity and port tokens
library ieee;
use ieee.std_logic_1164.all;

entity inline_entity_port is
    port (
        clk : in std_logic; -- comment after clk
        data_in : in std_logic_vector(7 downto 0); -- comment after data_in
        data_out : out std_logic_vector(7 downto 0) -- comment after data_out
    );
end entity inline_entity_port;

architecture rtl of inline_entity_port is
begin
    data_out <= data_in;
end architecture rtl;
