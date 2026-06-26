-- Test generic and port map with named association
library ieee;
use ieee.std_logic_1164.all;

entity generic_port_map is
    port (
        clk : in std_logic;
        data : inout std_logic_vector(31 downto 0)
    );
end entity generic_port_map;

architecture rtl of generic_port_map is
    component fifo is
        generic (
            DEPTH : integer;
            WIDTH : integer
        );
        port (
            clk : in std_logic;
            wr_en : in std_logic;
            rd_en : in std_logic;
            din : in std_logic_vector;
            dout : out std_logic_vector;
            full : out std_logic;
            empty : out std_logic
        );
    end component fifo;
    
    signal wr_en, rd_en, full, empty : std_logic;
begin
    -- Instantiation with both generic map and port map (named)
    u_fifo : fifo
        generic map (
            DEPTH => 16,
            WIDTH => 32
        )
        port map (
            clk => clk,
            wr_en => wr_en,
            rd_en => rd_en,
            din => data,
            dout => data,
            full => full,
            empty => empty
        );
end architecture rtl;
