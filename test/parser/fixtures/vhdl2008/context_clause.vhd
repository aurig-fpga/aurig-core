-- VHDL-2008 context clause (should be safely ignored by VHDL-93 parser)
context ieee.ieee_std_context;

entity test_context is
    port (
        clk : in std_logic;
        data : in std_logic_vector(7 downto 0)
    );
end entity test_context;

architecture rtl of test_context is
begin
    -- architecture content
end architecture rtl;
