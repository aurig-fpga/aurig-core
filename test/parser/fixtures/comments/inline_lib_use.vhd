-- Test comments between tokens in library and use
library -- comment after library
    ieee -- comment after ieee
    ; -- comment after semicolon
use -- comment after use
    ieee -- comment after ieee
    . -- comment after dot
    std_logic_1164 -- comment after package name
    . -- comment after dot
    all -- comment after all
    ; -- comment after semicolon

entity inline_lib_use is
    port (
        data : in std_logic
    );
end entity inline_lib_use;

architecture rtl of inline_lib_use is
begin
end architecture rtl;
