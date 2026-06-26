-- Multiple entities and architectures in one file
library ieee;
use ieee.std_logic_1164.all;

entity first_entity is
    port (
        clk : in std_logic;
        data_in : in std_logic
    );
end entity first_entity;

architecture rtl of first_entity is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- first entity logic
        end if;
    end process;
end architecture rtl;

-- Second entity in same file
library ieee;
use ieee.std_logic_1164.all;

entity second_entity is
    port (
        rst : in std_logic;
        data_out : out std_logic
    );
end entity second_entity;

architecture rtl of second_entity is
begin
    data_out <= '0' when rst = '1' else '1';
end architecture rtl;
