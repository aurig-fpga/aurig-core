-- Test library and use clauses with tokens split across lines
library
    ieee
    ;
use
    ieee
    .
    std_logic_1164
    .
    all
    ;

entity split_library_use is
    port (
        data : in std_logic
    );
end entity split_library_use;

architecture rtl of split_library_use is
begin
end architecture rtl;
