-- Function and procedure with split parameter lists
library ieee;
use ieee.std_logic_1164.all;

package pkg_split_params is
    
    -- Function with parameters split across lines
    function compute(
        a : integer;
        b : integer;
        c : integer
    ) return integer;
    
    -- Procedure with mixed line breaks
    procedure process_data(
        signal input : in std_logic_vector;
        signal output : out std_logic_vector;
        constant width : in integer := 8
    );
    
    -- Function with return type on new line
    function get_max(
        x : integer;
        y : integer
    ) 
    return integer;
    
end package pkg_split_params;
