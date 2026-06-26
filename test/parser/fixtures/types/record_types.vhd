-- Test record type declarations
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package record_pkg is
    -- Simple record
    type pixel is record
        red   : std_logic_vector(7 downto 0);
        green : std_logic_vector(7 downto 0);
        blue  : std_logic_vector(7 downto 0);
    end record pixel;
    
    -- Record with mixed types
    type packet is record
        valid  : std_logic;
        data   : std_logic_vector(31 downto 0);
        length : integer range 0 to 1023;
        parity : std_logic;
    end record packet;
    
    -- Nested record
    type address_info is record
        street : integer;
        city   : integer;
    end record address_info;
    
    type person is record
        age     : integer range 0 to 120;
        address : address_info;
    end record person;
    
    -- Record with comments
    type control_reg is record
        enable : std_logic;  -- enable bit
        reset  : std_logic;  -- reset bit
        mode   : std_logic_vector(1 downto 0);  -- mode selection
    end record control_reg;
end package record_pkg;
