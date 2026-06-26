-- Test entity instantiation (direct instantiation)
library ieee;
use ieee.std_logic_1164.all;

entity entity_inst is
    port (
        clk : in std_logic;
        data_in : in std_logic_vector(15 downto 0);
        data_out : out std_logic_vector(15 downto 0)
    );
end entity entity_inst;

architecture rtl of entity_inst is
begin
    -- Direct entity instantiation
    u_buffer : entity work.data_buffer
        port map (
            clk => clk,
            din => data_in,
            dout => data_out
        );
end architecture rtl;
