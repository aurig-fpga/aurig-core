-- Test complex nested type declarations
library ieee;
use ieee.std_logic_1164.all;

package nested_pkg is
    -- Record containing vectors
    type axi_master is record
        awaddr  : std_logic_vector(31 downto 0);
        awvalid : std_logic;
        awready : std_logic;
        wdata   : std_logic_vector(31 downto 0);
        wstrb   : std_logic_vector(3 downto 0);
        wvalid  : std_logic;
        wready  : std_logic;
    end record axi_master;
    
    -- Array of records
    type axi_array is array (0 to 3) of axi_master;
    
    -- Record containing array
    type fifo_status is record
        full    : std_logic;
        empty   : std_logic;
        count   : integer range 0 to 15;
        data    : std_logic_vector(7 downto 0);
    end record fifo_status;
    
    -- Subtype of record
    subtype input_fifo is fifo_status;
    
    -- Complex nested: record -> array -> record
    type inner_rec is record
        val : integer;
    end record inner_rec;
    
    type inner_array is array (0 to 3) of inner_rec;
    
    type outer_rec is record
        id    : integer;
        items : inner_array;
    end record outer_rec;
end package nested_pkg;
