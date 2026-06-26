-- Test component declaration and instantiation
library ieee;
use ieee.std_logic_1164.all;

entity comp_inst is
    port (
        clk : in std_logic;
        rst : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity comp_inst;

architecture rtl of comp_inst is
    -- Component declaration
    component my_register is
        port (
            clk : in std_logic;
            rst : in std_logic;
            d   : in std_logic_vector(7 downto 0);
            q   : out std_logic_vector(7 downto 0)
        );
    end component my_register;
    
    signal internal_data : std_logic_vector(7 downto 0);
begin
    -- Component instantiation with positional association
    u_reg : my_register
        port map (
            clk,
            rst,
            data_in,
            data_out
        );
end architecture rtl;
