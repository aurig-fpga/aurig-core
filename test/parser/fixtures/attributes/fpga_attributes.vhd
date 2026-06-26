-- Test common FPGA synthesis attributes
library ieee;
use ieee.std_logic_1164.all;

entity fpga_attributes is
    port (
        clk : in std_logic;
        rst : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity fpga_attributes;

architecture rtl of fpga_attributes is
    -- Xilinx-style attributes
    attribute KEEP : string;
    attribute DONT_TOUCH : string;
    attribute MAX_FANOUT : integer;
    attribute IOB : string;
    
    signal internal_reg : std_logic_vector(7 downto 0);
    signal keep_signal : std_logic;
    
    -- Apply attributes to signals
    attribute KEEP of internal_reg : signal is "TRUE";
    attribute DONT_TOUCH of keep_signal : signal is "TRUE";
    attribute MAX_FANOUT of clk : signal is 50;
    attribute IOB of data_out : signal is "TRUE";
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                internal_reg <= (others => '0');
            else
                internal_reg <= data_in;
            end if;
        end if;
    end process;
    
    data_out <= internal_reg;
    keep_signal <= rst;
end architecture rtl;
