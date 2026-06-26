-- Regression: an entity instantiation whose port map uses an attribute
-- selector (`signal'left`, `signal'range`, ...) inside an indexed actual.
-- The previous `_grab_paren_block` treated the lone `'` as a character
-- literal opener and scanned past the matching `)` of the port map looking
-- for a closing `'` that never came. Mirrored on the Era RAT
-- `ces_math_fix_to_fpu_sig.vhd` pattern.
library ieee;
use ieee.std_logic_1164.all;

entity attr_in_pm is
  port (
    clk_i  : in  std_logic;
    din_i  : in  std_logic_vector(7 downto 0);
    dout_o : out std_logic
  );
end entity attr_in_pm;

architecture rtl of attr_in_pm is
  component sub_block is
    port (
      clk     : in  std_logic;
      data_in : in  std_logic;
      data_out : out std_logic
    );
  end component sub_block;
begin
  inst_attr_bit : component sub_block
    port map (
      clk      => clk_i,
      data_in  => din_i(din_i'left),
      data_out => dout_o
    );
end architecture rtl;
