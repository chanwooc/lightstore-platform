import AuroraCommon::*;
import Leds::*;

interface Top_Pins;
	interface Aurora_Pins#(4) aurora_fmc1;
	interface Aurora_Clock_Pins aurora_clk_fmc1;
	interface LEDS leds;
endinterface
