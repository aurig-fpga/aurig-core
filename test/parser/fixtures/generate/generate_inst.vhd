-- Test generate with component instantiation
library ieee;
use ieee.std_logic_1164.all;

entity generate_with_inst is
    port (
        clk : in std_logic;
        din : in std_logic_vector(31 downto 0);
        dout : out std_logic_vector(31 downto 0)
    );
end entity generate_with_inst;

architecture rtl of generate_with_inst is
    component reg_slice is
        port (
            clk : in std_logic;
            d : in std_logic;
            q : out std_logic
        );
    end component reg_slice;
begin
    -- Generate creating multiple component instances
    gen_slices: for i in 0 to 31 generate
        u_slice : reg_slice
            port map (
                clk => clk,
                d => din(i),
                q => dout(i)
            );
    end generate gen_slices;
end architecture rtl;
