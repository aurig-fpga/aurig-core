-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2024-2026 LogiMentor S.r.l.
--=============================================================================
-- Module Name :
-- Library     :
-- Project     :
-- Company     :
-- Author      :
-------------------------------------------------------------------------------
-- Description  :
--
--
-------------------------------------------------------------------------------
-- Revision History:
-- Date        Version  Author         Description
--
--
--=============================================================================
library
ieee
;

LIBRAry iEee

;

use ieee.
std_logic_1164.
all

;


entity test_entity is
generic
( g_1 : integer :=
9;
g_2 : std_logic_vector(1 downto 0)
)
;
port( p_1 : in std_logic;
-- test comment before p_2
p_2 : integer := 0; -- test comment in p_2 line
p_3 : out std_logic_vector(2 downto 0));

end entity test_entity;

architecture a_test of test_entity is -- comment in a_test line
  signal s_1 : std_logic;
  -- function
  function mytest(test : in std_logic := '0'; test2 : boolean) return std_logic_vector is
    variable v_myvar : std_logic_vector(1 downto 0) := "00";
    constant C_INSIDE_FUNC_CONST : integer := 0;
  begin
    if test2 then
      if test = '0' then
        v_myvar := "01";
      else
        v_myvar := "00";
      end if;
    else
      v_myvar := "11";
    end if;
    return v_myvar;
  end;
  constant C_TEST : integer := 19; -- a cnstant

  -- tes comment signal s_2
  signal s_2 : std_logic_vector(14 downto 0) := "--0"&x"ACB"; --comment in s_2 line
  --
  signal s_3 : std_logic_vector(1 downto 0);
  shared variable v_myvar2 : std_logic_vector(1 downto 0) := "10";

  component my_test_com_decl is
    generic (
      G_COM_1 : integer := 5
    );
    port( p_a : in std_logic;
          p_b : out std_logic_vector(3 downto 0));
  end component;
begin

  -- test comment process
  proc_test: process(p_2)
   variable v_1 : boolean := true; -- test comment in v_1 -- line
  begin
    if rising_edge(p_1) then
      if p_1 = '0' then -- test comment in p_1 line
        s_1 <= p_1;
      else -- test comment in else line
        p_3 <= s_2(p_3'range);
      end if;
    end if;
  end process proc_test;

  assert false report "-- this is a string not a comment" severity note; -- this is a comment in report line


	process(s_1)
		function test(test : in std_logic := '0'; test2 : boolean) return std_logic_vector is
			variable v_myvar : std_logic_vector(1 downto 0) := "00";
		begin
			if test2 then
				if test = '0' then
					v_myvar := "01";
				else
					v_myvar := "00";
				end if;
			else
				v_myvar := "11";
			end if;
      return v_myvar;
		end;
	begin
		s_3 <= test(s_1,false);
	end process;

  -- instantiation section
  u_my_test_com_inst : my_test_com_decl
    generic map (
      G_COM_1 => 10
    )
    port map (
      p_a => s_1,
      p_b => s_3
    );

    -- direct instantiation
    u_my_test_com_inst2 : entity work.my_test_direct_inst
      generic map (
        G_COM_2 => 15,
        G_COM_3 => 20
      )
      port map (
        p_a => s_2(0),
        p_b => s_3
      );

end; -- architecture a_test
--=============================================================================
