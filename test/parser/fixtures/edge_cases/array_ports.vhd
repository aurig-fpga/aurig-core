-- Testing array types in ports
library ieee;
use ieee.std_logic_1164.all;

entity array_ports is
    generic (
        NUM_CHANNELS : integer := 4;
        DATA_WIDTH : integer := 8
    );
    port (
        clk : in std_logic;
        
        -- Array of std_logic
        enables : in std_logic_vector(NUM_CHANNELS-1 downto 0);
        
        -- Array of vectors (2D array)
        data_in : in std_logic_vector(NUM_CHANNELS*DATA_WIDTH-1 downto 0);
        data_out : out std_logic_vector(NUM_CHANNELS*DATA_WIDTH-1 downto 0)
    );
end entity array_ports;

architecture rtl of array_ports is
    type data_array_t is array (0 to NUM_CHANNELS-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal data_regs : data_array_t;
begin
    
    gen_channels : for i in 0 to NUM_CHANNELS-1 generate
        process(clk)
        begin
            if rising_edge(clk) then
                if enables(i) = '1' then
                    data_regs(i) <= data_in((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH);
                end if;
            end if;
        end process;
        
        data_out((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH) <= data_regs(i);
    end generate;
    
end architecture rtl;
