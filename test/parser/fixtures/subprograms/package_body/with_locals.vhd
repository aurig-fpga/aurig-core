-- Package body with function implementations
library ieee;
use ieee.std_logic_1164.all;

package pkg_implementations is
    function add(a : integer; b : integer) return integer;
    procedure set_value(signal data : out std_logic_vector; value : std_logic_vector);
end package pkg_implementations;

package body pkg_implementations is
    
    -- Function implementation with local variable
    function add(a : integer; b : integer) return integer is
        variable result : integer;
    begin
        result := a + b;
        return result;
    end function add;
    
    -- Procedure implementation with local constant
    procedure set_value(signal data : out std_logic_vector; value : std_logic_vector) is
        constant ZERO : std_logic_vector(data'range) := (others => '0');
    begin
        if value'length = data'length then
            data <= value;
        else
            data <= ZERO;
        end if;
    end procedure set_value;
    
end package body pkg_implementations;
