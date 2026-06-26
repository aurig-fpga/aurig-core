-- Testing record types in ports
library ieee;
use ieee.std_logic_1164.all;

package record_pkg is
    type bus_master_out is record
        address : std_logic_vector(31 downto 0);
        data : std_logic_vector(31 downto 0);
        write_enable : std_logic;
        read_enable : std_logic;
        valid : std_logic;
    end record;
    
    type bus_master_in is record
        data : std_logic_vector(31 downto 0);
        ready : std_logic;
        error : std_logic;
    end record;
end package record_pkg;

library ieee;
use ieee.std_logic_1164.all;
use work.record_pkg.all;

entity record_ports is
    port (
        clk : in std_logic;
        master_out : out bus_master_out;
        master_in : in bus_master_in
    );
end entity record_ports;

architecture rtl of record_ports is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            master_out.address <= (others => '0');
            master_out.data <= master_in.data;
            master_out.valid <= master_in.ready;
        end if;
    end process;
end architecture rtl;
