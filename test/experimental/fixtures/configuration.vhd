entity leaf is end leaf;
architecture rtl of leaf is begin end architecture;
entity top is end entity top;
architecture rtl of top is
  component leaf is end component;
begin
  u : leaf;
end rtl;
configuration configured of top is
  for rtl
    for u : leaf
      use entity work.leaf(rtl);
    end for;
  end for;
end configured;
