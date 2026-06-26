-- Test comment association with entity declaration
library ieee;
use ieee.std_logic_1164.all;

-- This comment should be associated with the entity
-- It's immediately preceding with no blank line
entity entity_comment_assoc is
    port (
        clk : in std_logic
    );
end entity entity_comment_assoc;

architecture rtl of entity_comment_assoc is
begin
end architecture rtl;
