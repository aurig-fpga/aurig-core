-- Simple block statement
library ieee;
use ieee.std_logic_1164.all;

entity simple_block is
    port (
        clk : in std_logic;
        data_in : in std_logic;
        data_out : out std_logic
    );
end entity simple_block;

architecture rtl of simple_block is
begin
    -- Block statement with guard
    block_label: block (clk = '1')
    begin
        data_out <= guarded data_in;
    end block block_label;
end architecture rtl;
