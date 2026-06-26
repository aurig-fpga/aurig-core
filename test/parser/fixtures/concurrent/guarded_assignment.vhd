-- Test concurrent assignments with guarded signals
library ieee;
use ieee.std_logic_1164.all;

entity guarded_assignment is
    port (
        clk : in std_logic;
        enable : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity guarded_assignment;

architecture rtl of guarded_assignment is
    signal guard_sig : boolean;
begin
    -- Guarded block
    guard_sig <= enable = '1';
    
    -- Guarded concurrent assignment
    data_out <= guarded data_in when guard_sig else
                (others => '0');
end architecture rtl;
