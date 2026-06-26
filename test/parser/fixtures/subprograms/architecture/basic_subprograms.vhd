-- Subprograms in architecture declarative region
library ieee;
use ieee.std_logic_1164.all;

entity arch_subprog_entity is
    port (
        clk : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity arch_subprog_entity;

architecture rtl of arch_subprog_entity is
    
    -- Function declared in architecture
    function reverse_byte(data : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable result : std_logic_vector(7 downto 0);
    begin
        for i in 0 to 7 loop
            result(i) := data(7-i);
        end loop;
        return result;
    end function reverse_byte;
    
    -- Procedure declared in architecture
    procedure latch_data(
        signal clk : in std_logic;
        signal input : in std_logic_vector(7 downto 0);
        signal output : out std_logic_vector(7 downto 0)
    ) is
    begin
        if rising_edge(clk) then
            output <= input;
        end if;
    end procedure latch_data;
    
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            data_out <= reverse_byte(data_in);
        end if;
    end process;
    
end architecture rtl;
