-- Entity with various vector types and ranges
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vector_types is
    port (
        -- std_logic_vector with downto
        slv_downto : in std_logic_vector(15 downto 0);
        
        -- std_logic_vector with to
        slv_to : in std_logic_vector(0 to 7);
        
        -- signed and unsigned
        signed_data : in signed(11 downto 0);
        unsigned_data : out unsigned(11 downto 0);
        
        -- Natural ranges
        index_downto : in integer range 15 downto 0;
        index_to : in integer range 0 to 31
    );
end entity vector_types;

architecture rtl of vector_types is
begin
    unsigned_data <= unsigned(signed_data);
end architecture rtl;
