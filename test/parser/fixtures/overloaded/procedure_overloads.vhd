-- Overloaded procedures with different parameter modes
library ieee;
use ieee.std_logic_1164.all;

package proc_overload_pkg is
    -- First overload: single output
    procedure reset(signal sig : out std_logic);
    
    -- Second overload: vector output
    procedure reset(signal vec : out std_logic_vector);
    
    -- Third overload: with enable
    procedure reset(
        signal sig : out std_logic;
        enable : in boolean
    );
    
    -- Fourth overload: inout parameter
    procedure reset(signal counter : inout integer);
end package proc_overload_pkg;

package body proc_overload_pkg is
    procedure reset(signal sig : out std_logic) is
    begin
        sig <= '0';
    end procedure reset;
    
    procedure reset(signal vec : out std_logic_vector) is
    begin
        vec <= (others => '0');
    end procedure reset;
    
    procedure reset(
        signal sig : out std_logic;
        enable : in boolean
    ) is
    begin
        if enable then
            sig <= '0';
        end if;
    end procedure reset;
    
    procedure reset(signal counter : inout integer) is
    begin
        counter <= 0;
    end procedure reset;
end package body proc_overload_pkg;
