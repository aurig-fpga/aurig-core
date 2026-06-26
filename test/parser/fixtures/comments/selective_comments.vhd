-- Test selective comment association (only some items have comments)
library ieee;
use ieee.std_logic_1164.all;

entity selective_comments is
    generic (
        WIDTH : integer := 8;
        -- Only DEPTH has a comment
        DEPTH : integer := 16;
        HEIGHT : integer := 32
    );
    port (
        clk : in std_logic;
        -- Only rst has a preceding comment
        rst : in std_logic;
        enable : in std_logic; -- Only enable has an end-of-line comment
        data_in : in std_logic_vector(WIDTH-1 downto 0);
        data_out : out std_logic_vector(WIDTH-1 downto 0);
        -- Only valid has a comment
        valid : out std_logic
    );
end entity selective_comments;

architecture rtl of selective_comments is
    signal reg1 : std_logic_vector(WIDTH-1 downto 0);
    -- Only reg2 has a comment
    signal reg2 : std_logic_vector(WIDTH-1 downto 0);
    signal reg3 : std_logic_vector(WIDTH-1 downto 0); -- Only reg3 has end-of-line
    signal reg4 : std_logic_vector(WIDTH-1 downto 0);
begin
    data_out <= reg4;
end architecture rtl;
