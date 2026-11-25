library ieee;
use ieee.std_logic_1164.all;
package composite_objects is
    signal resolved_vector : (resolved) std_ulogic_vector(7 downto 0);
    type vector_array is array (natural range <>) of bit_vector;
    signal matrix : vector_array(0 to 1)(7 downto 0);
    signal resolved_scalar : ieee.std_logic_1164.resolved std_ulogic;
end;
