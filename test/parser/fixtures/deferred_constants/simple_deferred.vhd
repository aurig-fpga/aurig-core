-- Deferred constant in package declaration, defined in package body
library ieee;
use ieee.std_logic_1164.all;

package deferred_pkg is
    -- Deferred constant (no value here)
    constant MAX_VALUE : integer;
    constant MIN_VALUE : integer;
    
    -- Regular constant for comparison
    constant MID_VALUE : integer := 128;
    
    function get_range return integer;
end package deferred_pkg;

package body deferred_pkg is
    -- Deferred constants completed here
    constant MAX_VALUE : integer := 255;
    constant MIN_VALUE : integer := 0;
    
    function get_range return integer is
    begin
        return MAX_VALUE - MIN_VALUE;
    end function get_range;
end package body deferred_pkg;
