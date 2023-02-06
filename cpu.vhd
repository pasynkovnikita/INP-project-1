-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Nikita Pasynkov <xpasyn00 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;
-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

-- CNT
	signal cnt_inc: std_logic;  						-- counter increment
	signal cnt_dec: std_logic;  						-- counter decrement
	signal cnt_clr: std_logic;  						-- counter clear
	signal cnt_reg: std_logic_vector(12 downto 0);     	-- counter register

-- PC
	signal pc_inc: std_logic;   						-- program counter increment
	signal pc_dec: std_logic;   						-- program counter decrement
	signal pc_clr: std_logic;  							-- program counter clear
	signal pc_reg: std_logic_vector(12 downto 0); 		-- program counter register

-- PTR
	signal ptr_inc: std_logic;  						-- pointer increment
	signal ptr_dec: std_logic;  						-- pointer decrement
	signal ptr_clr: std_logic;  						-- pointer clear
	signal ptr_reg: std_logic_vector(12 downto 0); 		-- pointer register

-- MX1
	signal mx1_sel: std_logic;   						-- mx1 select
	signal mx1_out: std_logic_vector(12 downto 0);    	-- mx1 choose between pc_reg and ptr_reg depending on mx1_sel ##not my comment

-- MX2
	signal mx2_sel: std_logic_vector(1 downto 0);     	-- mx1 select 
	signal mx2_out: std_logic_vector(7 downto 0);     	-- mx1 choose DATA_RDATA(increased ">" or decreased "<") or IN_DATA ##not my comment

	type fsm_state is (
        -- initial state
		s_idle,
        -- reading instruction
		s_i_fetch,
        -- decoding instruction
		s_i_decode,
        -- pointer increment >
		s_inc_ptr,
        -- pointer decrement <
		s_dec_ptr,
        -- increment the memory cell - +
		s_inc_0, s_inc_1, s_inc_2,
        -- decrement the memory cell - -
		s_dec_0, s_dec_1, s_dec_2,
        -- output from the memory cell
		s_putchar_0, s_putchar_1,
        -- input to the memory cell
		s_getchar_0, s_getchar_1,
        -- while loop
		s_while_0, s_while_1, s_while_2, s_while_3,
        -- end of while loop
        s_end_while_0, s_end_while_1, s_end_while_2, s_end_while_3,
        -- end of program
		s_halt,
        -- waiting to go to s_i_fetch
		wait_for_fetch,
        -- others
		s_others
	);

	-- present state
	signal fsm_pstate : fsm_state := s_idle; 
	-- next state
	signal fsm_nstate : fsm_state;


begin
	pc_cntr: process (CLK, RESET, pc_inc, pc_dec)
		begin
			if RESET = '1' then
				pc_reg <= (others => '0');
			elsif CLK'event and CLK = '1' then
				if pc_inc = '1' then
					pc_reg <= pc_reg + 1;
				elsif pc_dec = '1' then
					pc_reg <= pc_reg - 1;
				elsif pc_clr = '1' then
					pc_reg <= (others => '0');
				end if;
			end if;
		end process;

  	ptr_cntr: process (CLK, RESET, ptr_inc, ptr_dec)
		begin
			if RESET = '1' then
				ptr_reg <= (12 => '1', others => '0');
			elsif CLK'event and CLK = '1' then
				if ptr_inc = '1' then
					ptr_reg <= ptr_reg + 1;
				elsif ptr_dec = '1' then
					ptr_reg <= ptr_reg - 1;
				elsif ptr_clr = '1' then
					ptr_reg <= (others => '0');
				end if;
			end if;
		end process;

  	cnt_cntr: process (CLK, RESET, cnt_inc, cnt_dec)
		begin
			if RESET = '1' then
				cnt_reg <= (others => '0');
			elsif CLK'event and CLK = '1' then
				if cnt_inc = '1' then
					cnt_reg <= cnt_reg + 1;
				elsif cnt_dec = '1' then
					cnt_reg <= cnt_reg - 1;
				elsif cnt_clr = '1' then
					cnt_reg <= (others => '0');
				end if;
			end if;
		end process;

  	fsm_pstate_proc: process (CLK, RESET, EN)
		begin
			if RESET = '1' then
				fsm_pstate <= s_idle;
			elsif CLK'event and CLK = '1' then
				if EN = '1' then
					fsm_pstate <= fsm_nstate;
				end if;
			end if;
		end process;


  MX1: process (CLK, RESET, mx1_sel, ptr_reg, pc_reg)
    -- mx1_sel == 0 -> PC
    -- mx1_sel == 1 -> PTR

	begin
		if RESET = '1' then
			mx1_out <= (others => '0');
		elsif CLK'event and CLK = '1' then
			case mx1_sel is
				when '0' =>
					mx1_out <= pc_reg;
				when '1' =>
					mx1_out <= ptr_reg;
				when others => 
					mx1_out <= (others => '0');
			end case;
		end if;
	end process;

	MX2: process (CLK, RESET, mx2_sel, DATA_RDATA, IN_DATA)
    -- mx2_sel == 00 -> IN_DATA
    -- mx2_sel == 01 -> DATA_RDATA + 1
    -- mx2_sel == 10 -> DATA_RDATA - 1

	begin
		if RESET = '1' then
			mx2_out <= (others => '0');
		elsif CLK'event and CLK = '1' then
			case mx2_sel is
				when "00" =>
					mx2_out <= IN_DATA;
				when "01" =>
					mx2_out <= DATA_RDATA - 1;
				when "10" =>
					mx2_out <= DATA_RDATA + 1;
				when others =>
					mx2_out <= (others => '0');
			end case;
		end if;
	end process;

	-- DATA_ADDR <= mx1_out;
	-- DATA_WDATA <= mx2_out;
	-- OUT_DATA <= DATA_RDATA;

	fsm_nstate_proc: process (fsm_pstate, OUT_BUSY, IN_VLD, DATA_RDATA, cnt_reg, DATA_RDATA)
	begin

		-- INIT
		pc_inc <= '0';
		pc_dec <= '0';
		pc_clr <= '0';

		ptr_inc <= '0';
		ptr_dec <= '0';
		ptr_clr <= '0';

		cnt_inc <= '0';
		cnt_dec <= '0';
		cnt_clr <= '0';

		IN_REQ <= '0';
		OUT_WE <= '0';

		mx1_sel <= '0';
		mx2_sel <= "11";

		DATA_RDWR <= '0';
		DATA_EN <= '0';

		DATA_ADDR <= mx1_out;
		DATA_WDATA <= mx2_out;
		OUT_DATA <= DATA_RDATA;


		case fsm_pstate is
			when s_idle =>
				mx1_sel <= '0';
				DATA_RDWR <= '0';
				DATA_EN <= '1';

				fsm_nstate <= s_i_fetch;


			when s_i_fetch =>
				mx1_sel <= '1';
				DATA_RDWR <= '0';
				DATA_EN <= '1';

				fsm_nstate <= s_i_decode;


			when s_i_decode =>
				case DATA_RDATA is
					when X"3E" =>
						fsm_nstate <= s_inc_ptr; -- >
					when X"3C" =>
						fsm_nstate <= s_dec_ptr; -- <
					when X"2B" =>
						fsm_nstate <= s_inc_0; -- +
					when X"2D" =>
						fsm_nstate <= s_dec_0; -- -
					when X"5B" =>
						fsm_nstate <= s_while_0; -- [
					when X"5D" =>
						fsm_nstate <= s_end_while_0; -- ]
					when X"2E" =>
						fsm_nstate <= s_putchar_0; -- .
					when X"2C" =>
						fsm_nstate <= s_getchar_0; -- ,
					when X"00" =>
						fsm_nstate <= s_halt;
					when others =>
						fsm_nstate <= s_others;
				end case;

				IN_REQ <= '1';
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '0';
	

            -- pointer increase
			when s_inc_ptr =>
				ptr_inc <= '1';
				pc_inc <= '1';
				mx1_sel <= '1';

				fsm_nstate <= wait_for_fetch;

            -- pointer decrease
			when s_dec_ptr =>
				ptr_dec <= '1';
				pc_inc <= '1';
				mx1_sel <= '1';

				fsm_nstate <= wait_for_fetch;


            -- increase value at pointer
			when s_inc_0 =>
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '1';
				mx2_sel <= "10";
				pc_inc <= '1';

				fsm_nstate <= s_inc_1;

			when s_inc_1 =>
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';

				fsm_nstate <= s_i_fetch;
			
			when s_inc_2 =>
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '0';

				fsm_nstate <= s_i_fetch;


            -- decrease value at pointer
			when s_dec_0 =>
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '1';
				mx2_sel <= "01";
				pc_inc <= '1';

				fsm_nstate <= s_dec_1;

			when s_dec_1 =>
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '0';

				fsm_nstate <= s_i_fetch;
		
			when s_dec_2 =>
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				mx1_sel <= '0';
				
				fsm_nstate <= s_i_fetch;


			-- while loop
			when s_while_0 =>
				pc_inc <= '1';
				if DATA_RDATA = (DATA_RDATA'range => '0') then
					cnt_inc <= '0';

					fsm_nstate <= s_while_2;
				else
					fsm_nstate <= wait_for_fetch;
				end if;
      
			when s_while_1 => 
				DATA_EN <= '1';
				DATA_RDWR <= '0';

				fsm_nstate <= s_while_2;
        
			when s_while_2 =>
				pc_inc <= '1';
				if cnt_reg = (cnt_reg'range => '0') then
					fsm_nstate <= wait_for_fetch;
				else
					DATA_RDWR <= '0';

					fsm_nstate <= s_while_3;
				end if;
			
			when s_while_3 =>
				if cnt_reg = (cnt_reg'range => '0') then
					pc_inc <= '1';

					fsm_nstate <=  wait_for_fetch;
				else 
					if DATA_RDATA = X"5B" then
						cnt_inc <= '1';
					end if;

					if DATA_RDATA = X"5D" then
						cnt_dec <= '1';
					end if;

				fsm_nstate <= s_while_2;  
				end if;
      

	  		-- end of while loop
			when s_end_while_0 =>
				DATA_RDWR <= '0';
				if DATA_RDATA = (DATA_RDATA'range => '0') then
					pc_inc <= '1';

					fsm_nstate <= wait_for_fetch;
				else
					pc_dec <= '1';
					cnt_inc <= '1';

					fsm_nstate <= s_end_while_1;
				end if;

			when s_end_while_1 => 
				fsm_nstate <= s_end_while_2;
				
			when s_end_while_2 =>
				if cnt_reg = (cnt_reg'range => '0') then
					pc_inc <= '1';

					fsm_nstate <= wait_for_fetch;
				else
					DATA_EN <= '1';
					DATA_RDWR <= '0';
					pc_dec <= '1';

					fsm_nstate <= s_end_while_3;
				end if;

			when s_end_while_3 =>
				if cnt_reg = (cnt_reg'range => '0') then
					pc_inc <= '1';

					fsm_nstate <=  wait_for_fetch;
				else
					if DATA_RDATA = X"5B" then
						cnt_dec <= '1';
					end if;

					if DATA_RDATA = X"5D" then
						cnt_inc <= '1';
					end if;
					fsm_nstate <= s_end_while_2;  
				end if;
    
		
			when s_putchar_0 =>
				--
				if OUT_BUSY = '0' then
					OUT_WE <= '1';
					pc_inc <= '1';

					fsm_nstate <= wait_for_fetch;
				elsif OUT_BUSY = '1' then
					DATA_EN <= '1';
					DATA_RDWR <= '0';
					mx1_sel <= '1';

					fsm_nstate <= s_putchar_0;
				end if;
			
			when s_getchar_0 =>
				mx1_sel <= '1';
				if IN_VLD /= '1' then
					IN_REQ <= '1';

					fsm_nstate <= s_getchar_0;
				else
					mx2_sel <= "00";
					DATA_EN <= '1';
					DATA_RDWR <= '0';

					fsm_nstate <= s_getchar_1;
				end if;
  
			when s_getchar_1 =>
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				mx1_sel <= '1';	

				pc_inc <= '1';
				
				fsm_nstate <= wait_for_fetch;

			when wait_for_fetch =>
				fsm_nstate <= s_i_fetch;

			when others =>
				pc_inc <= '1';

				fsm_nstate <= wait_for_fetch;

		end case;
	end process;

end behavioral;