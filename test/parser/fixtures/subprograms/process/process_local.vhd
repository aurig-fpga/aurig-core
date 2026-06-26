-- Subprograms declared inside process
library ieee;
use ieee.std_logic_1164.all;

entity process_subprog is
    port (
        clk : in std_logic;
        input : in std_logic_vector(7 downto 0);
        output : out std_logic_vector(7 downto 0)
    );
end entity process_subprog;

architecture rtl of process_subprog is
begin
    
    process(clk)
        -- Function declared inside process
        function swap_nibbles(data : std_logic_vector(7 downto 0)) return std_logic_vector is
            variable result : std_logic_vector(7 downto 0);
        begin
            result(7 downto 4) := data(3 downto 0);
            result(3 downto 0) := data(7 downto 4);
            return result;
        end function swap_nibbles;
        
        -- Procedure declared inside process
        procedure increment_by_one(
            variable value : inout std_logic_vector(7 downto 0)
        ) is
        begin
            value := std_logic_vector(unsigned(value) + 1);
        end procedure increment_by_one;
        
        variable temp : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            temp := input;
            temp := swap_nibbles(temp);
            increment_by_one(temp);
            output <= temp;
        end if;
    end process;
    
end architecture rtl;
