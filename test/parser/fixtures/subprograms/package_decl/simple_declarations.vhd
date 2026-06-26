-- Function and procedure declarations in package
library ieee;
use ieee.std_logic_1164.all;

package pkg_subprog_decl is
    
    -- Simple function declaration
    function add(a : integer; b : integer) return integer;
    
    -- Function with default parameter
    function multiply(x : integer; factor : integer := 2) return integer;
    
    -- Simple procedure declaration
    procedure reset(signal clk : in std_logic; signal rst : out std_logic);
    
    -- Procedure with inout mode
    procedure toggle(signal flag : inout std_logic);
    
    -- Function with vector types
    function reverse_bits(data : std_logic_vector) return std_logic_vector;
    
end package pkg_subprog_decl;
