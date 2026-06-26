-- Test multi-line generic and port maps with comments
library ieee;
use ieee.std_logic_1164.all;

entity multiline_maps is
    port (
        clk : in std_logic;
        rst : in std_logic
    );
end entity multiline_maps;

architecture rtl of multiline_maps is
    component parameterized is
        generic (
            G_WIDTH : integer;
            G_DEPTH : integer;
            G_MODE : string
        );
        port (
            clk : in std_logic;
            rst : in std_logic;
            din : in std_logic_vector;
            dout : out std_logic_vector
        );
    end component parameterized;
    
    signal data_in, data_out : std_logic_vector(15 downto 0);
begin
    -- Multi-line maps with comments
    u_param : parameterized
        generic map (
            G_WIDTH => 16,        -- data width
            G_DEPTH => 32,        -- fifo depth
            G_MODE => "NORMAL"    -- operating mode
        )
        port map (
            clk  => clk,          -- system clock
            rst  => rst,          -- active high reset
            din  => data_in,      -- input data bus
            dout => data_out      -- output data bus
        );
end architecture rtl;
