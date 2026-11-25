library ieee;
use ieee.std_logic_1164.all;
entity e is port (o : out std_logic); end;
architecture rtl of e is
  signal logic_signal : std_logic := '0';
  alias ext is << signal .e.logic_signal : std_logic >>;
  constant nt : natural := 16#FF#;
  constant physics : real := 2#1.01#E-2;
begin
  o <= logic_signal when logic_signal ?= '1' else ext;
end;
