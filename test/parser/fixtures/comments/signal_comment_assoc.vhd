-- Test comment association with signals and constants
library ieee;
use ieee.std_logic_1164.all;

entity signal_comment_assoc is
    port (
        clk : in std_logic;
        data : in std_logic_vector(7 downto 0)
    );
end entity signal_comment_assoc;

architecture rtl of signal_comment_assoc is
    
    -- Initial value constant
    constant INIT_VALUE : std_logic_vector(7 downto 0) := x"00";
    
    constant MAX_COUNT : integer := 255; -- Maximum counter value
    
    -- This is the data register
    -- It stores the input data
    signal data_reg : std_logic_vector(7 downto 0);
    
    signal counter : integer range 0 to MAX_COUNT; -- Counter signal
    
    signal enable : std_logic;
    
    -- State machine state
    signal state : integer;
    
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            data_reg <= data;
        end if;
    end process;
    
end architecture rtl;
