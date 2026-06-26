-- Regression for PR #35 review round: VHDL string literals do NOT use
-- backslash escapes; a string ending with `\` is still a perfectly valid
-- string. The previous `_split_top_level_commas` / `_grab_paren_block`
-- string-state handling treated `\"` as an escape and skipped the closing
-- quote, leaving the scanner stuck "inside" the string and swallowing the
-- following association comma. With VHDL-correct semantics (doubled quotes
-- "" are the literal-quote escape, `\` is an ordinary character), the
-- generic map below must produce two separate associations even when the
-- first generic value ends with `\`.
library ieee;
use ieee.std_logic_1164.all;

entity str_trailing_bs is
  port (
    clk_i  : in  std_logic;
    dout_o : out std_logic
  );
end entity str_trailing_bs;

architecture rtl of str_trailing_bs is
  component sub_block is
    generic (
      g_path : string  := "default";
      g_id   : integer := 0
    );
    port (
      clk  : in  std_logic;
      dout : out std_logic
    );
  end component sub_block;
begin
  inst_bs : component sub_block
    generic map (
      g_path => "C:\",
      g_id   => 7
    )
    port map (
      clk  => clk_i,
      dout => dout_o
    );
end architecture rtl;
