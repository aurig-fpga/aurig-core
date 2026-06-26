-- Test concurrent assignments with comments and multi-line
library ieee;
use ieee.std_logic_1164.all;

entity multiline_concurrent is
    port (
        enable : in std_logic;
        mode : in std_logic_vector(1 downto 0);
        data_in : in std_logic_vector(15 downto 0);
        data_out : out std_logic_vector(15 downto 0)
    );
end entity multiline_concurrent;

architecture rtl of multiline_concurrent is
    signal processed : std_logic_vector(15 downto 0);
begin
    -- Multi-line conditional with comments
    processed <=
        data_in                     when enable = '1' and mode = "00" else  -- pass through
        data_in(14 downto 0) & '0'  when enable = '1' and mode = "01" else  -- shift left
        '0' & data_in(15 downto 1)  when enable = '1' and mode = "10" else  -- shift right
        (others => '0');                                                      -- default
    
    data_out <= processed;
end architecture rtl;
