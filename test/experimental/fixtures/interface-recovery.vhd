entity fix is
  generic (broken : ; width : natural := 3 suffix_a, suffix_b : integer := 2);
  port (a : bit; failed : out bit_vector(0 to 2) := (others => '0'; '1'); b : out bit);
end entity fix;
entity later is port (correct : bit); end;
