-- Multiple deferred constants with complex types
library ieee;
use ieee.std_logic_1164.all;

package complex_deferred_pkg is
    type state_type is (IDLE, ACTIVE, DONE);
    type config_array is array (0 to 3) of integer;
    
    -- Deferred constants of various types
    constant INITIAL_STATE : state_type;
    constant DEFAULT_CONFIG : config_array;
    constant ENABLE_MASK : std_logic_vector(7 downto 0);
    
    -- Mix with non-deferred
    constant TIMEOUT : integer := 1000;
end package complex_deferred_pkg;

package body complex_deferred_pkg is
    -- Complete deferred constants
    constant INITIAL_STATE : state_type := IDLE;
    constant DEFAULT_CONFIG : config_array := (10, 20, 30, 40);
    constant ENABLE_MASK : std_logic_vector(7 downto 0) := "11110000";
    
    -- Can add additional non-deferred constants in body
    constant INTERNAL_FLAG : boolean := true;
end package body complex_deferred_pkg;
