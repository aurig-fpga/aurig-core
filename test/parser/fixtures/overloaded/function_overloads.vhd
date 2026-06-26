-- Package with overloaded functions (same name, different signatures)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package overload_pkg is
    -- First overload: single bit
    function to_string(value : std_logic) return string;
    
    -- Second overload: vector
    function to_string(value : std_logic_vector) return string;
    
    -- Third overload: integer
    function to_string(value : integer) return string;
    
    -- Fourth overload: unsigned
    function to_string(value : unsigned) return string;
end package overload_pkg;

package body overload_pkg is
    function to_string(value : std_logic) return string is
    begin
        case value is
            when '0' => return "0";
            when '1' => return "1";
            when others => return "X";
        end case;
    end function to_string;
    
    function to_string(value : std_logic_vector) return string is
    begin
        return "vector of length " & integer'image(value'length);
    end function to_string;
    
    function to_string(value : integer) return string is
    begin
        return integer'image(value);
    end function to_string;
    
    function to_string(value : unsigned) return string is
    begin
        return "unsigned: " & integer'image(to_integer(value));
    end function to_string;
end package body overload_pkg;
