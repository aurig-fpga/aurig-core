-- Testing various comment styles and positions
library ieee;
use ieee.std_logic_1164.all;

-- This is a header comment
-- It spans multiple lines
-- And describes the entity

entity comment_test is
    port (
        clk : in std_logic;  -- Clock input
        rst : in std_logic;  -- Active high reset
        -- Data interface
        data_in : in std_logic_vector(7 downto 0);   -- Input data bus
        data_out : out std_logic_vector(7 downto 0)  -- Output data bus
        -- More comments here
    );
end entity comment_test;  -- End of entity

-- Architecture begins
architecture rtl of comment_test is
    -- Internal signals
    signal reg : std_logic_vector(7 downto 0);  -- Register
begin
    -- Main process
    process(clk)  -- Synchronous process
    begin
        if rising_edge(clk) then  -- On clock edge
            if rst = '1' then  -- Reset condition
                reg <= (others => '0');  -- Clear register
            else
                reg <= data_in;  -- Load data
            end if;
        end if;
    end process;  -- End of process
    
    -- Output assignment
    data_out <= reg;  -- Drive output
    
end architecture rtl;  -- End of architecture
