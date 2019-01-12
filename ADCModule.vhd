library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ADCModule is
	Port(
		-- Main clock which is used in the design
		clk_50Mhz : in STD_LOGIC;	-- Connect to Clock50MHz - V11
		
		-- For ADC-SPI Interface with Main Processor
		SCK : out STD_LOGIC; 
		CONVST : out STD_LOGIC;
		SDI : out STD_LOGIC;
		SDO : in STD_LOGIC;
		
		-- Testbench Parameter
		led_out : out STD_LOGIC_VECTOR(7 downto 0) := "00000000"		
	);
end entity;

architecture spiMaster_arc of ADCModule is

-- State List
type adc_state is (convert, acquire);
signal adc_state_sig : adc_state := convert;
signal clk_scaler : integer := 5;
signal clk_5Mhz : std_logic := '0';
signal scale_cnt : integer range 0 to 300 := 0;
signal counter : integer range 0 to 11 := 0;
signal SCK_sig : std_logic := '0';

signal adc_data_parallel : STD_LOGIC_VECTOR(11 downto 0);

signal din_byte : STD_LOGIC_VECTOR(0 to 5):= "110010";
signal din_index : integer range 0 to 5 := 0;

signal dout_index : integer range 0 to 11 := 0;


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
		else SCK <= '0';
		end if;
		if rising_edge (clk_5Mhz) then
			counter <= counter + 1;
			case adc_state_sig is				
				when convert => 
					if counter = 0 then
						CONVST <= '1';
						led_out <= adc_data_parallel(7 downto 0);
					elsif counter = 6 then
						adc_state_sig <= acquire;
						counter <= 0;
					else CONVST <= '0';									
					end if;

				when acquire =>
				if counter = 11 then
						adc_data_parallel(dout_index) <= SDO;
						dout_index <= 0;						
						adc_state_sig <= convert;
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
			end case;
		end if;	
	end process adc_proc;
	end spiMaster_arc;