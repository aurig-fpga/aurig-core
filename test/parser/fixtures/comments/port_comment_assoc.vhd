-- Test comment association with port declarations
library ieee;
use ieee.std_logic_1164.all;

entity port_comment_assoc is
    port (
        -- Clock input signal
        clk : in std_logic;
        
        rst : in std_logic; -- Active high reset
        
        -- Input data bus comment
        -- This is a multi-line comment
        data_in : in std_logic_vector(7 downto 0);
        
        data_out : out std_logic_vector(7 downto 0);
        
        -- Valid signal
        valid : out std_logic; -- Indicates data is valid
        
        ready : in std_logic
    );
end entity port_comment_assoc;

architecture rtl of port_comment_assoc is
begin
    data_out <= data_in;
    valid <= '1';
end architecture rtl;
