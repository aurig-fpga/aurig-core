-- SPDX-License-Identifier: Apache-2.0
-- Fixture: entity dup_top declared here AND in a.vhd (ambiguous top).
library ieee;
use ieee.std_logic_1164.all;

entity dup_top is
  port (rst : in std_logic);
end entity dup_top;

architecture rtl of dup_top is
begin
end architecture rtl;
