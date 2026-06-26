-- Regression: a generate statement with its own declarative section followed
-- by an internal `begin` (VHDL 1076-2008 §11.8 "generate_statement_body" form
-- that allows declarations). The previous parser collapsed the depth tracking
-- when type/signal tokens appeared after `generate` and then treated the
-- generate's own `begin` as a new nested block, leaving the architecture
-- end-search unbalanced. Mirrored on a real-drop Era RAT pattern
-- (`demo_util_delay.vhd`).
library ieee;
use ieee.std_logic_1164.all;

entity gen_decl_with_begin is
  generic (
    g_depth : natural := 4;
    g_width : natural := 8
  );
  port (
    clk_i  : in  std_logic;
    din_i  : in  std_logic_vector(g_width - 1 downto 0);
    dout_o : out std_logic_vector(g_width - 1 downto 0)
  );
end entity gen_decl_with_begin;

architecture rtl of gen_decl_with_begin is
begin
  gen_pipe : if g_depth > 1 generate
    type t_mem is array (0 to g_depth - 1) of std_logic_vector(din_i'range);
    signal s_mem : t_mem;
  begin
    proc_shift : process(clk_i)
    begin
      if rising_edge(clk_i) then
        s_mem(0) <= din_i;
        for i in 1 to g_depth - 1 loop
          s_mem(i) <= s_mem(i - 1);
        end loop;
      end if;
    end process proc_shift;

    dout_o <= s_mem(g_depth - 1);
  end generate gen_pipe;
end architecture rtl;
