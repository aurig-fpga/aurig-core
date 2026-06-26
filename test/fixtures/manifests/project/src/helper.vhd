-- SPDX-License-Identifier: Apache-2.0
-- Fixture: a second RTL entity that is NOT the top (must not be picked).
library ieee;
use ieee.std_logic_1164.all;

entity helper is
  port (
    a : in  std_logic;
    y : out std_logic
  );
end entity helper;

architecture rtl of helper is
begin
  y <= not a;
end architecture rtl;
