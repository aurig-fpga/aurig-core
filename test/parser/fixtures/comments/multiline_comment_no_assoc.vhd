-- XFAIL: Parser associates multi-line comments incorrectly
-- Expected: Multi-line comments should associate with immediately following declaration
-- Actual: Parser may not associate or associates with wrong declaration

library ieee;
use ieee.std_logic_1164.all;

entity comment_assoc_test is
  port (
    -- This is a multi-line comment
    -- that should associate with port_a
    -- but might not work correctly
    port_a : in std_logic;
    
    -- Single line for port_b
    port_b : in std_logic;
    
    port_c : in std_logic; -- This one should work
    
    port_d : out std_logic
  );
end entity comment_assoc_test;

architecture rtl of comment_assoc_test is
begin
  port_d <= port_a and port_b and port_c;
end architecture rtl;
