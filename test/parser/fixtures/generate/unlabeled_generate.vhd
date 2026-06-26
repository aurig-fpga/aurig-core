-- Test unlabeled generate statements
library ieee;
use ieee.std_logic_1164.all;

entity unlabeled_generate is
    port (
        clk : in std_logic;
        data : inout std_logic_vector(3 downto 0)
    );
end entity unlabeled_generate;

architecture rtl of unlabeled_generate is
    signal reg_data : std_logic_vector(3 downto 0);
begin
    -- Unlabeled for-generate (optional label)
    for i in 0 to 3 generate
        process(clk)
        begin
            if rising_edge(clk) then
                reg_data(i) <= data(i);
            end if;
        end process;
    end generate;
    
    data <= reg_data;
end architecture rtl;
