-- Test extreme token splitting within parser limits
library ieee;
use ieee.std_logic_1164.all;

entity extreme_split is
    generic (
        WIDTH
        :
        integer
        :=
        8
    );
    port (
        clk
        :
        in
        std_logic;
        data_in
        :
        in
        std_logic_vector
        (
        WIDTH
        -
        1
        downto
        0
        );
        data_out
        :
        out
        std_logic_vector
        (
        WIDTH
        -
        1
        downto
        0
        )
    );
end entity extreme_split;

architecture
    rtl
of
    extreme_split
is
    signal
        reg
    :
        std_logic_vector
        (
        WIDTH
        -
        1
        downto
        0
        );
begin
    reg
        <=
        data_in
        ;
    data_out
        <=
        reg
        ;
end architecture rtl;
