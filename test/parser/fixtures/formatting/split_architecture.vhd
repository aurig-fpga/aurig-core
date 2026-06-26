-- Test architecture with split declaration and body sections
library ieee;
use ieee.std_logic_1164.all;

entity split_architecture is
    port (
        clk : in std_logic;
        data_in : in std_logic;
        data_out : out std_logic
    );
end entity split_architecture;

architecture
    rtl
    of
    split_architecture
    is
    signal
        reg1
        :
        std_logic
        ;
    signal
        reg2
        :
        std_logic
        ;
begin
    
    process
        (
        clk
        )
    begin
        if
            rising_edge
            (
            clk
            )
        then
            reg1
            <=
            data_in
            ;
            reg2
            <=
            reg1
            ;
        end
            if
            ;
    end
        process
        ;
    
    data_out
        <=
        reg2
        ;
    
end
    architecture
    rtl
    ;
