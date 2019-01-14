---------------------------------------------------------------------------------------------------------------------------------------
-- The ADC interfacing to UART for DE0 Nano SoC Altera using FPGA only.
-- The data will be sent with this format: header, comma, thousands, hundreds, tens, ones (until 8 channel), new line.
-- Created by : Jason D. Setiawan, Bayu A. Pamungkas, Ubaid I. Najib N.F.
---------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity ADCModule is
	Port(
		-- Main clock which is used in the design
		clk_50Mhz : in std_logic;	-- Connect to Clock50MHz - V11
		
		-- For ADC-SPI Interface with Main Processor
		SCK : out std_logic; 		-- Connect to SCK - V10
		CONVST : out std_logic; 	-- Connect to CONVST - U9
		SDI : out std_logic;		-- Connect to SDI - AC4
		SDO : in std_logic;		-- Connect to SDO - AD4
		
		-- For Main Processor interface with PC through UART
		tx_out : out std_logic; 	-- Connect to GPIO_0[1] - AF7 
		
		-- Testbench Parameter (Only for checking)
--		led_out : out std_logic_vector (7 downto 0);
		clk_sck : out std_logic
--		state : out std_logic_vector (3 downto 0)
	);
end entity;

architecture spiMaster_arc of ADCModule is

-- Channel multiplexer
signal channel_index : integer range 0 to 7 := 0;

-- Multiplekser State List
type state is (header, adc, newline, delay);
signal state_sig : state := header;

-- State list
type adc_state is (convert, prepare, sending ,nap, acquire);
type prepare_state is (idle, check, shift, save);
type sending_state is (uart_start,start, data, stop); 
signal adc_state_sig : adc_state := convert;
signal prepare_state_sig : prepare_state := idle;
signal sending_state_sig : sending_state := uart_start;

-- Clock Modification Signal
signal clk_scaler : integer := 5; 
signal clk_5Mhz : std_logic := '0';
signal scale_cnt : integer range 0 to 300 := 0;
signal counter : integer range 0 to 11 := 0;
signal delays : integer range 0 to 5795 := 0;

-- Header
signal header_bits : std_logic_vector(7 downto 0) := x"41";
signal header_byte_cnt : integer range 0 to 10 := 0;

-- Newline
signal newline_bits : std_logic_vector(7 downto 0) := x"0A";
signal newline_byte_cnt : integer range 0 to 10 := 0;

-- Data Signal
signal adc_data_parallel : std_logic_vector(0 to 11);
signal din_byte : std_logic_vector(0 to 5);
signal din_index : integer range 0 to 5 := 0;
signal dout_index : integer range 0 to 11 := 0;

-- Preparation Signal
signal adc_data_modified : std_logic_vector(11 downto 0);
signal bcd : std_logic_vector (15 downto 0);
signal thousands : std_logic_vector (3 downto 0);
signal hundreds : std_logic_vector (3 downto 0);
signal tens : std_logic_vector (3 downto 0);
signal ones : std_logic_vector (3 downto 0);
signal cnt : integer range 0 to 11 := 0;

-- UART Signal
signal send_cnt : integer range 0 to 4;
signal uart_tx_data : STD_LOGIC_VECTOR(7 downto 0);
signal uart_byte_cnt : integer range 0 to 10 := 0;

begin
	clock_scale_proc : process(clk_50Mhz)
	begin
		if rising_edge(clk_50Mhz) then
			if scale_cnt = clk_scaler -1  then
				clk_5Mhz <= not(clk_5Mhz);
				scale_cnt <= 0;
			else
				scale_cnt <= scale_cnt + 1;
			end if;
		end if;
	end process clock_scale_proc;
	
	adc_proc : process (clk_5Mhz) 
	begin	
		if(adc_state_sig = acquire) then
			SCK <= clk_5Mhz;
			clk_sck <= clk_5Mhz;
		else SCK <= '0';
		end if;
		if rising_edge (clk_5Mhz) then
		
		case state_sig is
			when header =>				
				case sending_state_sig is
					when uart_start => 
--						state <= "0011";
						if header_byte_cnt = 0 then
							tx_out <= '1';							
							sending_state_sig <= start;
							clk_scaler <= 217;
						end if;
					when start =>
--						state <= "0100";
						tx_out <= '0';
						sending_state_sig <= data;
					when data =>
--						state <= "0101";
						if header_byte_cnt = 7 then
							tx_out <= header_bits(header_byte_cnt);
							header_byte_cnt <= 0;
							sending_state_sig <= stop;
						else
							tx_out <= header_bits(header_byte_cnt);						
							header_byte_cnt <= header_byte_cnt + 1;
						end if;
					when stop =>
--						state <= "0110";
						tx_out <= '1';
						channel_index <= 0;
						din_byte <= "000000";
						sending_state_sig <= uart_start;
						state_sig <= adc;
					end case;
					
			when adc =>
				
				counter <= counter + 1;
				case adc_state_sig is				
					when convert => 
--						state <= "0000";
						clk_scaler <= 5;
						if counter = 0 then
							CONVST <= '1';
--							led_out <= adc_data_parallel(0 to 7);											
						elsif counter = 6 then
							adc_state_sig <= acquire;
							counter <= 0;
						else CONVST <= '0';									
						end if;					
				when acquire =>
--					state <= "1000";
					case channel_index is
						when 0 => din_byte <= "110010";
						when 1 => din_byte <= "100110";
						when 2 => din_byte <= "110110";
						when 3 => din_byte <= "101010";
						when 4 => din_byte <= "111010";
						when 5 => din_byte <= "101110";
						when 6 => din_byte <= "111110";
						when 7 => din_byte <= "100010";
					end case;		
					if counter = 11 then
							adc_data_parallel(dout_index) <= SDO;
							dout_index <= 0;						
							adc_state_sig <= prepare;
							counter <= 0;						
						elsif counter > 5 then
							SDI <= '0';
							din_index <= 0;
							adc_data_parallel(dout_index) <= SDO;
							dout_index <= dout_index + 1;						
						else
							SDI <= din_byte(din_index);
							adc_data_parallel(dout_index) <= SDO;
							din_index <= din_index + 1;
							dout_index <= dout_index + 1;	
						end if;	

					-- Transforming the 12 bit parallel data read into BCD		
					when prepare => 
--						state <= "0001";						
						case prepare_state_sig is
							when idle =>
								-- Since the ADC transmit MSB first, we need to reverse the sequence.
								adc_data_modified <= adc_data_parallel(0 to 11);
								ones <= (others => '0');
								tens <= (others => '0');
								hundreds <= (others => '0');
								thousands <= (others => '0');
								bcd <= (others => '0');
								cnt <= 0;
								prepare_state_sig <= check;
							when check =>
								--ones
								if bcd(3 downto 0) > "0100" then
									bcd(3 downto 0) <= bcd(3 downto 0) + "0011";
								end if;
								--tens
								if bcd(7 downto 4) > "0100" then
									bcd(7 downto 4) <= bcd(7 downto 4) + "0011";
								end if;
								--hundreds
								if bcd(11 downto 8) > "0100" then
									bcd(11 downto 8) <= bcd(11 downto 8) + "0011";
								end if;
								--thousands
								if bcd(15 downto 12) > "0100" then
									bcd(15 downto 12) <= bcd(15 downto 12) + "0011";
								end if;
								prepare_state_sig <= shift;
							when shift =>
								if cnt <= 10 then 
									cnt <= cnt + 1;
									prepare_state_sig <= check;
									bcd <= bcd(14 downto 0) & adc_data_modified(11);
									adc_data_modified <= adc_data_modified(10 downto 0) & '0';
								else 
									bcd <= bcd(14 downto 0) & adc_data_modified(11);
									adc_data_modified <= adc_data_modified(10 downto 0) & '0';
									cnt <= 0;
									prepare_state_sig <= save;
								end if;
							when save =>
								ones <= bcd(3 downto 0);
								tens <= bcd(7 downto 4);
								hundreds <= bcd(11 downto 8);
								thousands <= bcd(15 downto 12);	
								prepare_state_sig <= idle;
								adc_state_sig <= sending;
								send_cnt <= 0;
						end case;					
							
					when sending => -- Data in : 1 byte, 7 clocking, out: 10 bit, 7clocking
--						state <= "0010";
						-- Send the transformed BCD with provided format through UART
						if send_cnt < 5 then
							case sending_state_sig is
								when uart_start =>
--									state <= "0011";
									if uart_byte_cnt = 0 then
									 tx_out <= '1';
									 counter <= 0;
									 send_cnt <= 0;
									 sending_state_sig <= start;
									end if;
								when start =>
--									state <= "0100";
									tx_out <= '0';
									sending_state_sig <= data;
									clk_scaler <= 217;
									case (send_cnt) is
										when 0 => uart_tx_data <= x"2c";
										when 1 => uart_tx_data <= x"3" & thousands;
										when 2 => uart_tx_data <= x"3" & hundreds;
										when 3 => uart_tx_data <= x"3" & tens;
										when 4 => uart_tx_data <= x"3" & ones;
										when others => uart_tx_data <= "00000000";
									end case;							  
								when data =>
--								  state <= "0101";
								  if uart_byte_cnt = 7 then
										tx_out <= uart_tx_data(uart_byte_cnt);
										uart_byte_cnt <= 0;
										sending_state_sig <= stop;
								  else
										tx_out <= uart_tx_data(uart_byte_cnt);						
										uart_byte_cnt<= uart_byte_cnt + 1;
								  end if;
								when stop =>
--								  state <= "0110";
								  tx_out <= '1';
								  if send_cnt = 4 then
									sending_state_sig <= uart_start;
									adc_state_sig <= nap;
								  else
									sending_state_sig <= start;
									send_cnt <= send_cnt + 1;
								  end if;
							end case;
						else
							send_cnt <= 0;
						end if;	
							
					when nap =>
--						state <= "0111";
						-- reset all the value back to zero.
						send_cnt <= 0;
						counter <= 0;
						uart_byte_cnt <= 0;						
						if channel_index < 7 then
							channel_index <= channel_index + 1;
							adc_state_sig <= convert;								
						elsif channel_index = 7 then
							adc_state_sig <= convert;
							state_sig <= newline;
						end if;
					end case;	
								
				when newline =>
					channel_index <= 0;
					case sending_state_sig is
					when uart_start => 
--						state <= "0011";
						if newline_byte_cnt = 0 then
							tx_out <= '1';							
							sending_state_sig <= start;
							clk_scaler <= 217;
						end if;
					when start =>
--						state <= "0100";
						tx_out <= '0';
						sending_state_sig <= data;
					when data =>
--						state <= "0101";
						if newline_byte_cnt = 7 then
							tx_out <= newline_bits(newline_byte_cnt);
							newline_byte_cnt <= 0;
							sending_state_sig <= stop;
						else
							tx_out <= newline_bits(newline_byte_cnt);						
							newline_byte_cnt <= newline_byte_cnt + 1;
						end if;
					when stop =>
--						state <= "0110";
						tx_out <= '1';
						sending_state_sig <= uart_start;
						state_sig <= delay;
					end case;
				when delay =>
					delays <= 0;
					if delays < 5793 then
						delays <= delays + 1;
					else 
						delays <= 0;
						state_sig <= header;
					end if;	
			end case;
		end if;	
	end process adc_proc;
	end spiMaster_arc;
