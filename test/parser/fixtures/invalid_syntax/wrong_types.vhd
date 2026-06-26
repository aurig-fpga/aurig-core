-- Invalid: incorrect type usage
library ieee;
use ieee.std_logic_1164.all;

entity wrong_types is
    port (
        -- Invalid: using integer as port type directly (needs range)
        count : in integer;
        
        -- Invalid: undefined type
        data : in undefined_type;
        
        -- Invalid: wrong direction keyword
        output : inward std_logic
    );
end entity wrong_types;

architecture rtl of wrong_types is
    -- Invalid: missing type
    signal sig1 : ;
    
    -- Invalid: wrong syntax for signal
    sig2 : std_logic;  -- missing 'signal' keyword
begin
end architecture rtl;
