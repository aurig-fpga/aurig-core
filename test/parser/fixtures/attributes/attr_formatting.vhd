-- Test attribute specifications with tricky formatting
library ieee;
use ieee.std_logic_1164.all;

entity attr_formatting is
    port (
        sig1 : in std_logic;
        sig2 : in std_logic;
        sig3 : in std_logic_vector(7 downto 0)
    );
end entity attr_formatting;

architecture rtl of attr_formatting is
    -- Attribute declarations with various formats
    attribute    MY_ATTR    :    string;
    attribute NUMERIC_ATTR : integer;
    
    -- Attribute specifications with whitespace
    attribute    MY_ATTR    of    sig1    :    signal    is    "value1";
    
    -- Attribute with comment
    attribute NUMERIC_ATTR of sig2 : signal is 42;  -- answer
    
    -- Multi-line attribute
    attribute MY_ATTR of sig3 : signal is
        "long_value";
begin
end architecture rtl;
