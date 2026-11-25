context c1 is library ieee; use ieee.std_logic_1164.all; end context c1;
context c2 is library ieee; use ieee.numeric_std.all; end c2;
context work.c1, work.c2; entity E is port (o : out std_logic); end;
architecture RTL of E is
  type guard_t is protected
    impure function value return integer;
  end protected guard_t;
  type guard_t is protected body
    impure function value return integer is begin return 2; end;
  end protected body guard_t;
  type scaled is range 0 to 10 units metre; end units scaled;
  signal s : std_logic_vector(3 downto 0) := 4UX"F";
begin
  g : if first: true generate
    b : block is begin
      p : process is
        procedure q is begin
          again : loop exit again; end loop again;
        end procedure q;
      begin
        case? s is when "1111" => q; when others => null; end case?;
        wait;
      end process p;
    end block b;
  end first;
  else second: generate
    assert true;
  end second;
  end generate g;
  choose : case 1 generate
    when branch_a: 1 =>
      assert true;
    end branch_a;
    when others =>
      assert false;
  end generate choose;
end architecture RTL;
package template is generic (n : integer); end package;
package instance is new work.template generic map ((1 + 2));
