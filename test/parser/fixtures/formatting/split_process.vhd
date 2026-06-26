-- Test process with line breaks in sensitivity list and statements
library ieee;
use ieee.std_logic_1164.all;

entity split_process is
    port (
        clk : in std_logic;
        rst : in std_logic;
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity split_process;

architecture rtl of split_process is
    signal reg : std_logic_vector(7 downto 0);
begin
    
    process
    (
        clk
        ,
        rst
    )
    begin
        if
            rst
            =
            '1'
        then
            reg
            <
            =
            (
            others
            =>
            '0'
            )
            ;
        elsif
            rising_edge
            (
            clk
            )
        then
            reg
            <=
            data_in
            ;
        end
            if
            ;
    end
        process
        ;
    
    data_out <= reg;
    
end architecture rtl;
