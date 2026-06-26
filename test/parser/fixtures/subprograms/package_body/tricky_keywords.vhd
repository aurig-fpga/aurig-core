-- Functions and procedures with misleading content in strings/comments
library ieee;
use ieee.std_logic_1164.all;

package pkg_tricky is
    
    -- Function with "procedure" in comment
    -- This is not a procedure, it's a function
    function not_a_procedure(x : integer) return integer;
    
    -- Procedure with "function return" in comment
    procedure not_a_function(signal data : out std_logic);
    
    -- Function name contains keyword-like text
    function end_of_data(data : std_logic_vector) return boolean;
    
end package pkg_tricky;

package body pkg_tricky is
    
    function not_a_procedure(x : integer) return integer is
        constant MSG : string := "procedure inside string";
    begin
        -- Comment with keywords: function procedure return signal
        return x + 1;
    end function not_a_procedure;
    
    procedure not_a_function(signal data : out std_logic) is
        constant RESET : string := "function return in string";
    begin
        data <= '0';
    end procedure not_a_function;
    
    function end_of_data(data : std_logic_vector) return boolean is
    begin
        return data = (data'range => '0');
    end function end_of_data;
    
end package body pkg_tricky;
