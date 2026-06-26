-- Test mixed positional and named association
library ieee;
use ieee.std_logic_1164.all;

entity mixed_association is
    port (
        clk : in std_logic;
        data : in std_logic_vector(7 downto 0)
    );
end entity mixed_association;

architecture rtl of mixed_association is
    component adder is
        port (
            a : in std_logic_vector(7 downto 0);
            b : in std_logic_vector(7 downto 0);
            cin : in std_logic;
            sum : out std_logic_vector(7 downto 0);
            cout : out std_logic
        );
    end component adder;
    
    signal result : std_logic_vector(7 downto 0);
    signal carry : std_logic;
begin
    -- Mixed positional and named (positional must come first)
    u_add : adder
        port map (
            data,                -- positional: a
            x"42",              -- positional: b
            '0',                -- positional: cin
            sum => result,      -- named
            cout => carry       -- named
        );
end architecture rtl;
