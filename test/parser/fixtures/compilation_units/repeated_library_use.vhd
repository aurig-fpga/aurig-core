-- Multiple library/use clauses throughout file
library ieee;
use ieee.std_logic_1164.all;

entity top_level is
    port (
        input : in std_logic
    );
end entity top_level;

architecture rtl of top_level is
begin
    -- architecture content
end architecture rtl;

-- Repeated library/use before next entity
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sub_module is
    port (
        data : in unsigned(7 downto 0)
    );
end entity sub_module;

architecture rtl of sub_module is
begin
    -- sub module content
end architecture rtl;

-- Yet another library/use block
library ieee;
use ieee.std_logic_1164.all;

package constants is
    constant CLK_FREQ : integer := 100_000_000;
end package constants;
