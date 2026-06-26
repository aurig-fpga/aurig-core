-- Mixed overloads: functions and procedures with operators
library ieee;
use ieee.std_logic_1164.all;

package mixed_overload_pkg is
    -- Overloaded "+"  operator
    function "+"(left, right : std_logic) return std_logic;
    function "+"(left : std_logic; right : integer) return std_logic;
    
    -- Overloaded "and" with different return types
    function "and"(left, right : std_logic) return std_logic;
    function "and"(left, right : std_logic_vector) return std_logic_vector;
    
    -- Regular function overloads
    function convert(value : std_logic) return integer;
    function convert(value : integer) return std_logic;
    function convert(value : std_logic_vector) return integer;
end package mixed_overload_pkg;

package body mixed_overload_pkg is
    function "+"(left, right : std_logic) return std_logic is
    begin
        return left or right;
    end function "+";
    
    function "+"(left : std_logic; right : integer) return std_logic is
    begin
        if right > 0 then
            return left;
        else
            return '0';
        end if;
    end function "+";
    
    function "and"(left, right : std_logic) return std_logic is
    begin
        return left and right;
    end function "and";
    
    function "and"(left, right : std_logic_vector) return std_logic_vector is
    begin
        return left and right;
    end function "and";
    
    function convert(value : std_logic) return integer is
    begin
        if value = '1' then
            return 1;
        else
            return 0;
        end if;
    end function convert;
    
    function convert(value : integer) return std_logic is
    begin
        if value /= 0 then
            return '1';
        else
            return '0';
        end if;
    end function convert;
    
    function convert(value : std_logic_vector) return integer is
    begin
        return value'length;
    end function convert;
end package body mixed_overload_pkg;
