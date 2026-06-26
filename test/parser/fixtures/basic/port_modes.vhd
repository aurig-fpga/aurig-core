-- Entity with different port modes
library ieee;
use ieee.std_logic_1164.all;

entity port_modes is
    port (
        -- Input ports
        input_signal : in std_logic;
        input_vector : in std_logic_vector(3 downto 0);
        
        -- Output ports
        output_signal : out std_logic;
        output_vector : out std_logic_vector(3 downto 0);
        
        -- Inout ports
        bidir_signal : inout std_logic;
        bidir_vector : inout std_logic_vector(7 downto 0);
        
        -- Buffer port
        buffer_signal : buffer std_logic
    );
end entity port_modes;

architecture rtl of port_modes is
begin
    output_signal <= input_signal;
    output_vector <= input_vector;
end architecture rtl;
