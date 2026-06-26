-- Architecture with internal signals and constants
library ieee;
use ieee.std_logic_1164.all;

entity internal_signals is
    port (
        clk : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity internal_signals;

architecture rtl of internal_signals is
    -- Constants
    constant INIT_VALUE : std_logic_vector(7 downto 0) := x"00";
    constant MAX_COUNT : integer := 255;
    
    -- Signals
    signal data_reg : std_logic_vector(7 downto 0);
    signal counter : integer range 0 to MAX_COUNT;
    signal enable : std_logic;
    
begin
    -- Synchronous process
    process(clk)
    begin
        if rising_edge(clk) then
            data_reg <= data_in;
            counter <= counter + 1;
        end if;
    end process;
    
    -- Combinational
    data_out <= data_reg when enable = '1' else INIT_VALUE;
    
end architecture rtl;
