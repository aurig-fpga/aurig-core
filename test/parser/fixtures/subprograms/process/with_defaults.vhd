-- Complex process with multiple subprograms
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity process_complex is
    port (
        clk, rst : in std_logic;
        data : inout std_logic_vector(15 downto 0)
    );
end entity process_complex;

architecture rtl of process_complex is
begin
    
    main_proc: process(clk, rst)
        -- Helper function with default parameter
        function mask_bits(
            value : std_logic_vector(15 downto 0);
            mask : std_logic_vector(15 downto 0) := x"00FF"
        ) return std_logic_vector is
        begin
            return value and mask;
        end function mask_bits;
        
        -- Procedure to set specific bits
        procedure set_bit(
            variable data : inout std_logic_vector;
            constant index : in natural
        ) is
        begin
            if index < data'length then
                data(index) := '1';
            end if;
        end procedure set_bit;
        
        -- Function to count ones
        function count_ones(value : std_logic_vector) return integer is
            variable count : integer := 0;
        begin
            for i in value'range loop
                if value(i) = '1' then
                    count := count + 1;
                end if;
            end loop;
            return count;
        end function count_ones;
        
        variable internal : std_logic_vector(15 downto 0);
    begin
        if rst = '1' then
            data <= (others => '0');
        elsif rising_edge(clk) then
            internal := data;
            set_bit(internal, 5);
            data <= mask_bits(internal);
        end if;
    end process main_proc;
    
end architecture rtl;
