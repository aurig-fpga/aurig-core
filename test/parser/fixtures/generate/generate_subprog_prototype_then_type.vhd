-- Regression: a generate declarative section that contains a subprogram
-- prototype (`function f return integer;`) followed by another declaration
-- whose right-hand side uses `is` (e.g. `type t is array (...) of ...`).
-- The previous Phase 2 scanner armed `sub_pending` on the first `is` after
-- seeing `function`, without checking whether a `;` had already closed the
-- prototype. As a result, the generate body's `begin` was misclassified as a
-- subprogram body opener and `split_arch_decl_body` finished one depth high.
library ieee;
use ieee.std_logic_1164.all;

entity gen_proto_then_type is
  generic (
    g_en : boolean := true
  );
  port (
    clk_i  : in  std_logic;
    dout_o : out std_logic
  );
end entity gen_proto_then_type;

architecture rtl of gen_proto_then_type is
begin
  gen_x : if g_en generate
    function f return integer;
    type t_my is array (0 to 7) of integer;
    signal s : t_my;
  begin
    proc1 : process(clk_i)
    begin
      if rising_edge(clk_i) then
        dout_o <= '1';
      end if;
    end process proc1;
  end generate gen_x;
end architecture rtl;
