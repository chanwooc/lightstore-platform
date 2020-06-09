`include "ConnectalProjectConfig.bsv"
import AuroraCommon::*;
// import ControllerTypes::*;
// import Leds::*;


interface Top_Pins;
	interface Aurora_Pins#(4) aurora_fmc1;         // 4-bit wide RXN/RXP_in & TXN/TXP_out
	interface Aurora_Clock_Pins aurora_clk_fmc1;   // 2 methods: gt_clk_p / gt_clk_n (Bit#(1) v)
`ifdef TWO_FLASH_CARDS
	interface Aurora_Pins#(4) aurora_fmc2;
	interface Aurora_Clock_Pins aurora_clk_fmc2;
`endif
endinterface
