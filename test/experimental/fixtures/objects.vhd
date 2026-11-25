package objects is
    constant deferred_a, deferred_b : integer;
    constant semi : character := ';'; constant message : string := "end; variable := ";
    constant quoted : character := character'('"');
    type lock_type is protected
        procedure touch;
    end protected;
    shared variable lock : lock_type;
    subtype nibble is bit_vector(3 downto 0);
end package;

package body objects is
    constant deferred_a : integer := 1;
    constant deferred_b : integer := 2;
    type lock_type is protected body
        procedure touch is
            variable protected_local : integer := 0;
        begin
            null;
        end procedure;
    end protected body;
    function computation(constant arg : integer) return integer is
        variable local_a, local_b :
          -- selected type
          std.standard.integer := 0;
        procedure helper is
            constant helper_only : integer := 3;
        begin
            null;
        end procedure;
    begin
        return local_a + local_b + arg;
    end function;
end package body;

entity object_test is
    generic (n : integer := 4);
    port (signal pin : in bit);
    constant entity_only : natural := n;
end;

library ieee;
use ieee.std_logic_1164.all;
architecture rtl of object_test is
    signal vector_a, \Vector B\ : std.standard.bit_vector((2 + 1) downto 0) := "0000";
    signal bus_a : std_logic bus := '0';
    signal reg_a : std_logic register;
    signal room : integer range 0 to 63 := 10;
begin
    p: process (pin) is
        variable process_a, process_b : integer;
        constant process_only : natural := 2;
    begin
        process_a := process_only;
    end process;
    block_i: block is
        signal block_only : bit;
    begin
    end block;
end architecture;
