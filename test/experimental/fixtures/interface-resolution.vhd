package resolved_types is
  function inward(values : bit_vector) return bit;
end package;
use work.resolved_types.all;
entity resolved_example is
  port (x : inward bit);
end;
