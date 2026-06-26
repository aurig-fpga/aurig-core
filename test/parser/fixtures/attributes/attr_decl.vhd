-- Test attribute declarations
library ieee;
use ieee.std_logic_1164.all;

package attr_pkg is
    -- Declare custom attributes
    attribute ENUM_ENCODING : string;
    attribute MAX_FANOUT : integer;
    attribute TIMING_CONSTRAINT : time;
    attribute IS_CRITICAL : boolean;
end package attr_pkg;

library ieee;
use ieee.std_logic_1164.all;
use work.attr_pkg.all;

entity attr_decl is
    port (
        clk : in std_logic;
        data : in std_logic_vector(7 downto 0)
    );
end entity attr_decl;

architecture rtl of attr_decl is
    type state_type is (IDLE, ACTIVE, DONE);
    
    -- Attribute specifications
    attribute ENUM_ENCODING of state_type : type is "one_hot";
    attribute MAX_FANOUT of clk : signal is 100;
    attribute IS_CRITICAL of data : signal is true;
begin
end architecture rtl;
