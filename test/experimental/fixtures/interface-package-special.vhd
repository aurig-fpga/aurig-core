package map_seed is generic (width : natural := 4); end package;
entity map_forms is
  generic (package defaults is new work.map_seed generic map (default);
           package free_map is new work.map_seed generic map (<>));
end entity;
