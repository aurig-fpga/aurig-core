package seed is
  generic (width : natural := 4);
  type row is array (natural range <>) of bit;
  type table is array (natural range <>) of row;
end package;
entity advanced is
  generic (
    type item;
    function "+" parameter (left, right : item) return item is <>;
    impure function read_item (constant where_i : in natural; flag : bit := '0') return item;
    procedure send (variable value : out item; p : in bit);
    package fixed_map is new work.seed generic map (width => (2 + 2));
    fill : bit := '0'
  );
  port (
    matrix : in fixed_map.table(0 to 1)(0 to 3) := (0 => (others => fill), others => (others => '1'));
    individual : in item
  );
end;
