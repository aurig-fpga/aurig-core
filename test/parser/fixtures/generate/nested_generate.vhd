-- Test nested generate statements
library ieee;
use ieee.std_logic_1164.all;

entity nested_generate is
    port (
        clk : in std_logic;
        matrix_in : in std_logic_vector(15 downto 0);
        matrix_out : out std_logic_vector(15 downto 0)
    );
end entity nested_generate;

architecture rtl of nested_generate is
    type matrix_type is array (0 to 3, 0 to 3) of std_logic;
    signal matrix : matrix_type;
begin
    -- Nested for-generate creating 2D array of registers
    gen_rows: for row in 0 to 3 generate
        gen_cols: for col in 0 to 3 generate
            process(clk)
            begin
                if rising_edge(clk) then
                    matrix(row, col) <= matrix_in(row * 4 + col);
                end if;
            end process;
            
            matrix_out(row * 4 + col) <= matrix(row, col);
        end generate gen_cols;
    end generate gen_rows;
end architecture rtl;
