-- Overloaded functions with different signatures
library ieee;
use ieee.std_logic_1164.all;

package pkg_overload is
    
    -- Overloaded to_integer function
    function to_integer(data : std_logic) return integer;
    function to_integer(data : std_logic_vector) return integer;
    
    -- Overloaded print procedure
    procedure print(message : string);
    procedure print(value : integer);
    procedure print(data : std_logic_vector);
    
end package pkg_overload;

package body pkg_overload is
    
    function to_integer(data : std_logic) return integer is
    begin
        if data = '1' then
            return 1;
        else
            return 0;
        end if;
    end function to_integer;
    
    function to_integer(data : std_logic_vector) return integer is
        variable result : integer := 0;
    begin
        for i in data'range loop
            result := result * 2;
            if data(i) = '1' then
                result := result + 1;
            end if;
        end loop;
        return result;
    end function to_integer;
    
    procedure print(message : string) is
    begin
        report message;
    end procedure print;
    
    procedure print(value : integer) is
    begin
        report "Value: " & integer'image(value);
    end procedure print;
    
    procedure print(data : std_logic_vector) is
    begin
        report "Vector length: " & integer'image(data'length);
    end procedure print;
    
end package body pkg_overload;
