-- Real literals and scientific notation (tests empty entity)
library ieee;
use ieee.std_logic_1164.all;

entity real_literals is
end entity real_literals;

architecture rtl of real_literals is
    -- Basic real literals
    constant R1 : real := 3.14159;
    constant R2 : real := 0.5;
    constant R3 : real := 123.456;
    
    -- Scientific notation
    constant R4 : real := 1.0E6;   -- 1 million
    constant R5 : real := 2.5E-3;  -- 0.0025
    constant R6 : real := 1.23E+4; -- 12300
    
    -- Edge cases
    constant R7 : real := 0.0;
    constant R8 : real := 1.0E0;   -- 1.0
    constant R9 : real := 9.99E99; -- very large
    
    -- With underscores
    constant R10 : real := 1_000_000.5;
    constant R11 : real := 1.234_567_89;
    
    -- Integer literals with underscores
    constant I1 : integer := 1_000_000;
    constant I2 : integer := 16#FF_FF#;
    constant I3 : integer := 2#1111_1111#;
begin
end architecture rtl;
