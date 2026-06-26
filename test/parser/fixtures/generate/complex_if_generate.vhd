-- Test generate with complex if-else structure
library ieee;
use ieee.std_logic_1164.all;

entity complex_if_generate is
    generic (
        DATA_WIDTH : integer := 8;
        USE_PARITY : boolean := false
    );
    port (
        clk : in std_logic;
        data_in : in std_logic_vector(DATA_WIDTH-1 downto 0);
        data_out : out std_logic_vector(DATA_WIDTH-1 downto 0);
        parity_out : out std_logic
    );
end entity complex_if_generate;

architecture rtl of complex_if_generate is
    signal parity : std_logic;
begin
    -- Main data path
    process(clk)
    begin
        if rising_edge(clk) then
            data_out <= data_in;
        end if;
    end process;
    
    -- Optional parity generation
    gen_parity: if USE_PARITY generate
        process(data_in)
            variable p : std_logic;
        begin
            p := '0';
            for i in 0 to DATA_WIDTH-1 loop
                p := p xor data_in(i);
            end loop;
            parity <= p;
        end process;
        
        parity_out <= parity;
    end generate gen_parity;
    
    gen_no_parity: if not USE_PARITY generate
        parity_out <= '0';
    end generate gen_no_parity;
end architecture rtl;
