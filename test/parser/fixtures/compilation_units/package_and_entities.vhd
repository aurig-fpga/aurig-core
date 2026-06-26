-- Package, package body, and entities in one file
library ieee;
use ieee.std_logic_1164.all;

package util_pkg is
    function to_bool(value : std_logic) return boolean;
    constant MAX_COUNT : integer := 255;
end package util_pkg;

package body util_pkg is
    function to_bool(value : std_logic) return boolean is
    begin
        return value = '1';
    end function to_bool;
end package body util_pkg;

-- Entity after package
library ieee;
use ieee.std_logic_1164.all;
use work.util_pkg.all;

entity counter is
    generic (
        WIDTH : integer := 8
    );
    port (
        clk : in std_logic;
        count : out integer range 0 to MAX_COUNT
    );
end entity counter;

architecture rtl of counter is
    signal cnt : integer range 0 to MAX_COUNT := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if cnt = MAX_COUNT then
                cnt <= 0;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;
    
    count <= cnt;
end architecture rtl;
