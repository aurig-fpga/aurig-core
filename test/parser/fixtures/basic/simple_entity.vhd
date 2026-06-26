-- Simple entity with basic ports
library ieee;
use ieee.std_logic_1164.all;

entity simple_entity is
    port (
        clk : in std_logic;
        rst : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity simple_entity;

architecture rtl of simple_entity is
begin
    process(clk, rst)
    begin
        if rst = '1' then
            data_out <= (others => '0');
        elsif rising_edge(clk) then
            data_out <= data_in;
        end if;
    end process;
end architecture rtl;
