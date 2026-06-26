-- Subprogram declarations with comments
library ieee;
use ieee.std_logic_1164.all;

package pkg_with_comments is
    
    -- This function adds two integers
    -- Returns the sum
    function add(a : integer; b : integer) return integer;
    
    -- Reset procedure
    procedure reset(signal rst : out std_logic); -- Active high reset
    
    -- Function with inline parameter comments
    function scale(
        value : integer;  -- Input value
        factor : integer := 10  -- Scale factor
    ) return integer;
    
end package pkg_with_comments;
