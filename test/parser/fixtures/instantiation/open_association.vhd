-- Test port map with 'open' and 'others =>' association
library ieee;
use ieee.std_logic_1164.all;

entity open_others is
    port (
        clk : in std_logic;
        input : in std_logic_vector(7 downto 0);
        output : out std_logic_vector(7 downto 0)
    );
end entity open_others;

architecture rtl of open_others is
    component complex_block is
        port (
            clk : in std_logic;
            rst : in std_logic;
            enable : in std_logic;
            data_in : in std_logic_vector(7 downto 0);
            data_out : out std_logic_vector(7 downto 0);
            status : out std_logic_vector(3 downto 0);
            debug : out std_logic_vector(15 downto 0)
        );
    end component complex_block;
    
    signal status_sig : std_logic_vector(3 downto 0);
begin
    -- Instantiation with 'open' for unused outputs
    u_block : complex_block
        port map (
            clk => clk,
            rst => '0',
            enable => '1',
            data_in => input,
            data_out => output,
            status => status_sig,
            debug => open  -- unused output
        );
end architecture rtl;
