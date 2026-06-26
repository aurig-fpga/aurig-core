-- Multiple subprograms in architecture with comments
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arch_multi is
    port (
        a, b : in std_logic_vector(3 downto 0);
        result : out std_logic_vector(3 downto 0)
    );
end entity arch_multi;

architecture rtl of arch_multi is
    
    -- Add two 4-bit vectors
    function add4(x, y : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable sum : unsigned(3 downto 0);
    begin
        sum := unsigned(x) + unsigned(y);
        return std_logic_vector(sum);
    end function add4;
    
    -- Subtract two 4-bit vectors
    function sub4(x, y : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable diff : unsigned(3 downto 0);
    begin
        diff := unsigned(x) - unsigned(y);
        return std_logic_vector(diff);
    end function sub4;
    
    -- Check if value is zero
    function is_zero(data : std_logic_vector) return boolean is
    begin
        return unsigned(data) = 0;
    end function is_zero;
    
begin
    
    result <= add4(a, b);
    
end architecture rtl;
