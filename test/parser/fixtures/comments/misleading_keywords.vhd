-- Test comments with misleading keywords
library ieee;
use ieee.std_logic_1164.all;

-- This comment mentions entity but it's just a comment
entity misleading_comments is
    generic (
        -- This generic comment says "end entity port" but it's fake
        WIDTH : integer := 8 -- Another comment with "signal constant architecture"
    );
    port (
        -- Comment with "process begin if then else end" keywords
        clk : in std_logic; -- "library use package" in comment
        -- Comment says "entity is port generic end" 
        data : in std_logic_vector(WIDTH-1 downto 0) -- "architecture of begin end"
    );
end entity misleading_comments;

-- Architecture comment with "entity port generic signal constant"
architecture rtl of misleading_comments is
    -- Signal comment mentions "process if then elsif end"
    signal reg : std_logic_vector(WIDTH-1 downto 0); -- "entity architecture end"
begin
    -- Process comment with "entity port architecture end signal"
    process(clk)
    begin
        -- Inside process, comment says "entity end architecture"
        if rising_edge(clk) then -- "entity port generic"
            reg <= data; -- Comment: "end entity end architecture"
        end if; -- "entity"
    end process; -- "end entity"
end architecture rtl; -- "entity port generic signal"
