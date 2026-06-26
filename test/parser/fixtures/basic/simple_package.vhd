-- Simple package declaration
library ieee;
use ieee.std_logic_1164.all;

package simple_package is
    
    -- Constants
    constant DATA_WIDTH : integer := 8;
    constant ADDR_WIDTH : integer := 10;
    
    -- Type declarations
    type state_type is (IDLE, ACTIVE, DONE);
    type data_array is array (natural range <>) of std_logic_vector(DATA_WIDTH-1 downto 0);
    
    -- Function declaration
    function increment(value : integer) return integer;
    
    -- Procedure declaration
    procedure reset_data(signal data : out std_logic_vector);
    
end package simple_package;

package body simple_package is
    
    function increment(value : integer) return integer is
    begin
        return value + 1;
    end function increment;
    
    procedure reset_data(signal data : out std_logic_vector) is
    begin
        data <= (others => '0');
    end procedure reset_data;
    
end package body simple_package;
