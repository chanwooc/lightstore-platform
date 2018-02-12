package AuroraCommon;

import FIFO::*;
import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;
import ConnectalXilinxCells::*;
import ConnectalClocks::*;
`include "ConnectalProjectConfig.bsv"

typedef 2 AuroraExtCount;
//typedef 4 AuroraExtQuad; // defined in zynq_multinode (?)

/* Example ClockDiv Code */
interface ClockDiv4Ifc;
	interface Clock slowClock;
endinterface

(* synthesize *)
module mkClockDiv4#(Clock fastClock) (ClockDiv4Ifc);
	MakeResetIfc fastReset <- mkReset(8, True, fastClock);
	ClockDividerIfc clockdiv4 <- mkClockDivider(4, clocked_by fastClock, reset_by fastReset.new_rst);
	Clock bufg <- mkClockBUFG(clocked_by clockdiv4.slowClock);

	interface slowClock = bufg;
endmodule

/* Aurora-related Pins */
`ifndef BSIM
(* always_enabled, always_ready *)
`endif
interface Aurora_Pins#(numeric type lanes);
	(* prefix = "" *)
	method Action rxn_in((* port = "RXN" *) Bit#(lanes) rxn_i);
	(* prefix = "" *)
	method Action rxp_in((* port = "RXP" *) Bit#(lanes) rxp_i);

	(* result = "TXN" *)
	method Bit#(lanes) txn_out();
	(* result = "TXP" *)
	method Bit#(lanes) txp_out();
endinterface

`ifndef BSIM
(* always_enabled, always_ready *)
`endif
interface Aurora_Clock_Pins;
	method Action gt_clk_p(Bit#(1) v);
	method Action gt_clk_n(Bit#(1) v);
	
	/* below to be removed by script -- needed for Action methods above */
	// interface Clock gt_clk_p_deleteme_unused_clock;
	// interface Clock gt_clk_n_deleteme_unused_clock;
endinterface

/* Aurora User Interface */
interface AuroraStatus#(numeric type lanes);
	method Bit#(1) channel_up;
	method Bit#(lanes) lane_up;
	method Bit#(1) hard_err;
	method Bit#(1) soft_err;
	method Bit#(8) data_err_count; 
endinterface

interface AuroraUserIfc#(numeric type lanes, numeric type width);
	//interface Reset aurora_rst_n; # not needed at the first place?
	interface AuroraStatus#(lanes) status;

	method Action send(Bit#(width) tx);
	method ActionValue#(Bit#(width)) receive();
endinterface

/* Interfaces for BVI wrapper */
interface AuroraImportIfc#(numeric type lanes);
	interface Clock aurora_clk;
	interface Reset aurora_rst;
	(* prefix = "" *)
	interface Aurora_Pins#(lanes) aurora;
	(* prefix = "" *)
	interface AuroraUserIfc#(lanes, TMul#(lanes,32)) user;
endinterface

interface AuroraExtImportIfc#(numeric type lanes);
	interface Clock aurora_clk0;
	interface Clock aurora_clk1;
	interface Clock aurora_clk2;
	interface Clock aurora_clk3;
	interface Reset aurora_rst0;
	interface Reset aurora_rst1;
	interface Reset aurora_rst2;
	interface Reset aurora_rst3;

	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora0;
	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora1;
	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora2;
	(* prefix = "" *)
	interface Aurora_Pins#(1) aurora3;
	(* prefix = "" *)
	interface AuroraUserIfc#(4, 64) user0;
	(* prefix = "" *)
	interface AuroraUserIfc#(4, 64) user1;
	(* prefix = "" *)
	interface AuroraUserIfc#(4, 64) user2;
	(* prefix = "" *)
	interface AuroraUserIfc#(4, 64) user3;

	`ifdef BSIM
	method Action setNodeIdx(Bit#(8) idx);
	`endif
endinterface

/* GT clock import */
interface GtClockImportIfc;
	interface Aurora_Clock_Pins aurora_clk;
	interface Clock gt_clk_p_ifc;
	interface Clock gt_clk_n_ifc;
endinterface

(* synthesize *)
module mkGtClockImport (GtClockImportIfc);
`ifndef BSIM
	B2C1 i_gt_clk_p <- mkB2C1();
	B2C1 i_gt_clk_n <- mkB2C1();

	Clock clk <- exposeCurrentClock;

	interface Aurora_Clock_Pins aurora_clk;
		method Action gt_clk_p(Bit#(1) v) = i_gt_clk_p.inputclock(v);
		method Action gt_clk_n(Bit#(1) v) = i_gt_clk_n.inputclock(v);

		// These clocks are deleted from the netlist by the synth.tcl script
		// interface Clock gt_clk_p_deleteme_unused_clock = clk;
		// interface Clock gt_clk_n_deleteme_unused_clock = clk;
	endinterface

	interface Clock gt_clk_p_ifc = i_gt_clk_p.c;
	interface Clock gt_clk_n_ifc = i_gt_clk_n.c;
`else
	Clock clk <- exposeCurrentClock;
	
	interface Aurora_Clock_Pins aurora_clk;
		method Action gt_clk_p(Bit#(1) v) = noAction;
		method Action gt_clk_n(Bit#(1) v) = noAction;

		// These clocks are deleted from the netlist by the synth.tcl script
		// interface Clock gt_clk_p_deleteme_unused_clock = clk; 
		// interface Clock gt_clk_n_deleteme_unused_clock = clk;
	endinterface

	interface Clock gt_clk_p_ifc = clk;
	interface Clock gt_clk_n_ifc = clk;
`endif
endmodule

endpackage: AuroraCommon
