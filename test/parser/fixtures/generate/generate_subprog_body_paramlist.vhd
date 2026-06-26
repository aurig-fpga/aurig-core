-- Regression for PR #35 Copilot review: a subprogram body inside a generate
-- declarative section whose parameter list contains a legitimate `;`
-- separator (`procedure p(a : integer; b : integer) is`). The prototype-vs-
-- body check that clears `saw_subprog_kw` must skip semicolons inside the
-- parameter list parens; otherwise the parameter `;` is mistaken for the
-- prototype terminator, `sub_pending` is never armed, and the generate's
-- own `begin` is misclassified as the procedure's body opener.
library ieee;
use ieee.std_logic_1164.all;

entity gen_subprog_body_paramlist is
  generic (
    g_en : boolean := true
  );
  port (
    clk_i  : in  std_logic;
    dout_o : out std_logic
  );
end entity gen_subprog_body_paramlist;

architecture rtl of gen_subprog_body_paramlist is
begin
  gen_x : if g_en generate
    procedure log_pair(a : integer; b : integer) is
      variable v : integer;
    begin
      v := a + b;
    end procedure log_pair;

    signal s_tick : std_logic;
  begin
    proc_drive : process(clk_i)
    begin
      if rising_edge(clk_i) then
        s_tick <= '1';
        dout_o <= s_tick;
      end if;
    end process proc_drive;
  end generate gen_x;
end architecture rtl;
