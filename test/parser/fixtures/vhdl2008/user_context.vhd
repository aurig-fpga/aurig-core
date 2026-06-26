-- User-defined context declaration (VHDL-2008)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

context my_design_context is
    library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
end context my_design_context;

-- Entity using context
context work.my_design_context;

entity context_user is
    port (
        input : in std_logic
    );
end entity context_user;

architecture rtl of context_user is
begin
    -- content
end architecture rtl;
