import AuroraCommon::*;
import Leds::*;

interface Top_Pins;
	interface Aurora_Pins#(4) aurora_fmc0;         // 4-bit wide RXN/RXP_in & TXN/TXP_out
	interface Aurora_Clock_Pins aurora_clk_fmc0;   // 2 methods: gt_clk_p / gt_clk_n (Bit#(1) v)
	interface LEDS leds;
endinterface
