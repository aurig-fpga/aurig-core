-- Block with declarations
library ieee;
use ieee.std_logic_1164.all;

entity block_with_declarations is
    port (
        clk : in std_logic;
        input : in std_logic_vector(7 downto 0);
        output : out std_logic_vector(7 downto 0)
    );
end entity block_with_declarations;

architecture rtl of block_with_declarations is
begin
    processing_block: block
        -- Declarations within block
        constant OFFSET : integer := 4;
        signal temp : std_logic_vector(7 downto 0);
    begin
        temp <= input;
        
        process(clk)
        begin
            if rising_edge(clk) then
                output <= temp(7-OFFSET downto 0) & temp(7 downto 8-OFFSET);
            end if;
        end process;
    end block processing_block;
end architecture rtl;
