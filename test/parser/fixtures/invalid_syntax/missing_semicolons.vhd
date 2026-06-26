-- Invalid: missing semicolons
library ieee
use ieee.std_logic_1164.all  -- missing semicolon

entity missing_semicolons is
    port (
        clk : in std_logic
        data : in std_logic  -- missing semicolon
    );
end entity missing_semicolons;

architecture rtl of missing_semicolons is
    signal temp : std_logic  -- missing semicolon
begin
    temp <= clk and data
end architecture rtl;  -- missing semicolon before end
