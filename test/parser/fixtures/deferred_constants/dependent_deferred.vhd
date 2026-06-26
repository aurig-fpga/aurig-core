-- Deferred constants with dependencies
library ieee;
use ieee.std_logic_1164.all;

package dependent_deferred_pkg is
    -- First deferred constant
    constant BASE_ADDR : integer;
    
    -- Second deferred constant that depends on first (in body)
    constant END_ADDR : integer;
    
    -- Non-deferred that can be computed from deferred (illegal in declaration)
    type addr_range is record
        start : integer;
        finish : integer;
    end record;
    
    constant FULL_RANGE : addr_range;
end package dependent_deferred_pkg;

package body dependent_deferred_pkg is
    constant BASE_ADDR : integer := 16#1000#;
    constant END_ADDR : integer := BASE_ADDR + 255;
    
    constant FULL_RANGE : addr_range := (
        start => BASE_ADDR,
        finish => END_ADDR
    );
end package body dependent_deferred_pkg;
