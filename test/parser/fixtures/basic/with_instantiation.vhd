-- Entity with component instantiation
library ieee;
use ieee.std_logic_1164.all;

entity with_instantiation is
    port (
        clk : in std_logic;
        rst : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity with_instantiation;

architecture rtl of with_instantiation is
    
    component simple_entity is
        port (
            clk : in std_logic;
            rst : in std_logic;
            data_in : in std_logic_vector(7 downto 0);
            data_out : out std_logic_vector(7 downto 0)
        );
    end component;
    
    signal internal_data : std_logic_vector(7 downto 0);
    
begin
    
    -- Component instantiation
    u_simple : simple_entity
        port map (
            clk => clk,
            rst => rst,
            data_in => data_in,
            data_out => internal_data
        );
    
    data_out <= internal_data;
    
end architecture rtl;
