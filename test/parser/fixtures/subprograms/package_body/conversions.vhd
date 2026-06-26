-- Package body with complex implementations
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pkg_complex is
    function to_slv(value : integer; width : integer) return std_logic_vector;
    function from_slv(data : std_logic_vector) return integer;
end package pkg_complex;

package body pkg_complex is
    
    -- Convert integer to std_logic_vector
    function to_slv(value : integer; width : integer) return std_logic_vector is
        variable temp : unsigned(width-1 downto 0);
    begin
        temp := to_unsigned(value, width);
        return std_logic_vector(temp);
    end function to_slv;
    
    -- Convert std_logic_vector to integer
    function from_slv(data : std_logic_vector) return integer is
        variable temp : unsigned(data'length-1 downto 0);
        variable result : integer;
    begin
        temp := unsigned(data);
        result := to_integer(temp);
        return result;
    end function from_slv;
    
end package body pkg_complex;
