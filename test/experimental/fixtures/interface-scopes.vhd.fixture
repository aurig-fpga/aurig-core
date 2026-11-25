entity leaf is generic (width : natural := 2); port (output : out bit); end entity;
architecture rtl of leaf is begin output <= '0'; end architecture;
entity wrapper is port (out_bit : out bit); end;
architecture top of wrapper is
  component leaf is
    generic (component_width : natural := 2);
    port (component_output : out bit);
  end component;
begin
  u : entity work.leaf generic map (width => 3) port map (output => out_bit);
end architecture;
