library ieee;
use ieee.std_logic_1164.all;
entity sample is
  generic (constant WIDTH, Depth : in natural := 4;
           label_text : string := "x);"";";
           marker : character := character '(')');
           other : character := '"');
  port (signal source_a, \B;Field\ : std.standard.bit;
        result_o : out bit_vector(WIDTH - 1 downto 0) := (others => '0');
        live : inout std_logic bus;
        shadow : buffer bit;
        opaque_i : linkage bit);
end entity sample;
