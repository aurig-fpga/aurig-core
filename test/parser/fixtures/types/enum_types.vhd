-- Test enumerated type declarations
library ieee;
use ieee.std_logic_1164.all;

package enum_pkg is
    -- Simple enumeration
    type state_type is (IDLE, ACTIVE, DONE);
    
    -- Enumeration with many values
    type opcode is (ADD, SUB, MUL, DIV, AND_OP, OR_OP, XOR_OP, NOT_OP);
    
    -- Enumeration with single value
    type singleton is (ONLY_ONE);
    
    -- Enumeration with comments
    type color is (
        RED,    -- primary
        GREEN,  -- primary
        BLUE    -- primary
    );
    
    -- Enumeration with split formatting
    type direction is (
        NORTH,
        SOUTH,
        EAST,
        WEST
    );
end package enum_pkg;
