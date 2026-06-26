-- Test type declarations with extreme whitespace and comments
library ieee;
use ieee.std_logic_1164.all;

package whitespace_pkg is
    -- Type with tokens split
    type
        state_machine
    is (
        RESET,
        INIT,
        RUN
    );
    
    -- Record with extreme spacing
    type    spaced_rec    is    record
        field1    :    std_logic;
        field2    :    integer;
    end    record    spaced_rec;
    
    -- Array with comment mid-declaration
    type memory is array  -- comment here
        (0 to 255)  -- size comment
    of std_logic_vector(7 downto 0);  -- element type
    
    -- Subtype with split constraint
    subtype limited_int is integer
        range 0
        to 100;
end package whitespace_pkg;
