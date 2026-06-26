-- Test attributes on different object classes
library ieee;
use ieee.std_logic_1164.all;

entity attr_classes is
    port (
        port1 : in std_logic
    );
end entity attr_classes;

architecture rtl of attr_classes is
    -- Attributes for different classes
    attribute ATTR_TYPE : string;
    attribute ATTR_SIGNAL : string;
    attribute ATTR_CONSTANT : string;
    attribute ATTR_VARIABLE : string;
    attribute ATTR_COMPONENT : string;
    
    type my_type is (A, B, C);
    signal my_signal : std_logic;
    constant my_const : integer := 10;
    
    component my_comp is
        port (x : in std_logic);
    end component my_comp;
    
    -- Attribute specifications for different classes
    attribute ATTR_TYPE of my_type : type is "enumeration";
    attribute ATTR_SIGNAL of my_signal : signal is "critical";
    attribute ATTR_CONSTANT of my_const : constant is "timing";
    attribute ATTR_COMPONENT of my_comp : component is "synthesizable";
begin
end architecture rtl;
