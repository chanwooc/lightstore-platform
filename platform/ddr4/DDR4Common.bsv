////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2013  Bluespec, Inc.  ALL RIGHTS RESERVED.
////////////////////////////////////////////////////////////////////////////////
//  Filename      : DDR4.bsv
//  Description   : 
////////////////////////////////////////////////////////////////////////////////

// Notes : Modified by Shoutao and Chanwoo

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import Clocks ::*;
import FIFO ::*;
import FIFOF ::*;
import SpecialFIFOs ::*;
import TriState ::*;
import DefaultValue ::*;
import Counter ::*;
import CommitIfc ::*;
import Memory ::*;
import GetPut ::*;
import ClientServer ::*;
import BUtils ::*;
import I2C ::*;
import Connectable ::*;

import XilinxCells ::*;
import ConnectalClocks ::*;
// import Cntrs::*;

////////////////////////////////////////////////////////////////////////////////
/// Exports
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
/// Types
////////////////////////////////////////////////////////////////////////////////
typedef struct {
	Bool simulation;
	Integer reads_in_flight;
} DDR4_Configure;

instance DefaultValue#(DDR4_Configure);
	defaultValue = DDR4_Configure {
		simulation: False,
		reads_in_flight: 16
	};
endinstance

typedef struct {
	Bool rnw;
	Bit#(bewidth)    byteen;
	Bit#(addrwidth)  address;
	Bit#(datawidth)  data;
} DDR4Request#(numeric type addrwidth, numeric type datawidth, numeric type bewidth) deriving (Bits, Eq);

typedef struct {
	Bit#(datawidth)  data;
} DDR4Response#(numeric type datawidth) deriving (Bits, Eq);

`define DDR4_PRM_DCL numeric type ddr4addrsize,\
					numeric type ddr4datasize,\
					numeric type ddr4besize,\
					numeric type addr_width,\
					numeric type row_width,\
					numeric type bank_width,\
					numeric type bank_group_width,\
					numeric type s_height,\
					numeric type lr_width,\
					numeric type cke_width,\
					numeric type ck_width,\
					numeric type col_width,\
					numeric type cs_width,\
					numeric type odt_width,\
					numeric type dq_width,\
					numeric type dqs_width,\
					numeric type dm_width


`define DDR4_PRM ddr4addrsize,\
				ddr4datasize,\
				ddr4besize,\
				addr_width,\
				row_width,\
				bank_width,\
				bank_group_width,\
				s_height,\
				lr_width,\
				cke_width,\
				ck_width,\
				col_width,\
				cs_width,\
				odt_width,\
				dq_width,\
				dqs_width,\
				dm_width

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////
(* always_enabled, always_ready *)
interface DDR4_Pins#(`DDR4_PRM_DCL);
	(* prefix = "", result = "ddr4_act_n" *)
	method Bit#(1) act_n;
	(* prefix = "", result = "ddr4_adr" *)
	method Bit#(addr_width) adr;
	(* prefix = "", result = "ddr4_ba" *)
	method Bit#(bank_width) ba;
	(* prefix = "", result = "ddr4_bg" *)
	method Bit#(bank_group_width) bg;
	(* prefix = "", result = "ddr4_cke" *)
	method Bit#(cke_width) cke;
	(* prefix = "", result = "ddr4_odt" *)
	method Bit#(odt_width) odt;
	(* prefix = "", result = "ddr4_cs_n" *)
	method Bit#(cs_width) cs_n;
	(* prefix = "", result = "ddr4_ck_t" *)
	method Bit#(ck_width) ck_t;
	(* prefix = "", result = "ddr4_ck_c" *)
	method Bit#(ck_width) ck_c;
	(* prefix = "", result = "ddr4_reset_n" *)
	method Bit#(1) reset_n;
	(* prefix = "ddr4_dm_dbi_n" *)
	interface Inout#(Bit#(dm_width)) dm_dbi_n;
	(* prefix = "ddr4_dq" *)
	interface Inout#(Bit#(dq_width)) dq;
	(* prefix = "ddr4_dqs_c" *)
	interface Inout#(Bit#(dqs_width)) dqs_c;
	(* prefix = "ddr4_dqs_t" *)
	interface Inout#(Bit#(dqs_width)) dqs_t;
endinterface


interface DDR4_User#(`DDR4_PRM_DCL);
	interface Clock clock;
	interface Reset reset_n;
	method Bool init_done;
	method Action request(Bit#(ddr4addrsize) addr,
						Bit#(ddr4besize) mask,
						Bit#(ddr4datasize) data
					);
	method ActionValue#(Bit#(ddr4datasize)) read_data;
endinterface

interface DDR4_Controller#(`DDR4_PRM_DCL);
	(* prefix = "" *)
	interface DDR4_Pins#(`DDR4_PRM) ddr4;
	(* prefix = "" *)
	interface DDR4_User#(`DDR4_PRM) user;
endinterface

(* always_ready, always_enabled *)
interface VDDR4_User_Xilinx#(`DDR4_PRM_DCL);
	interface Clock clock;
	interface Reset reset;
	method Bool init_done;
	method Action app_addr(Bit#(ddr4addrsize) i);
	method Action app_cmd(Bit#(3) i);
	method Action app_en(Bool i);
	method Action app_hi_pri(Bit#(1) i);
	method Action app_wdf_data(Bit#(ddr4datasize) i);
	method Action app_wdf_end(Bool i);
	method Action app_wdf_mask(Bit#(ddr4besize) i);
	method Action app_wdf_wren(Bool i);
	method Bit#(ddr4datasize) app_rd_data;
	method Bool app_rd_data_end;
	method Bool app_rd_data_valid;
	method Bool app_rdy;
	method Bool app_wdf_rdy; 
endinterface

interface VDDR4_Controller_Xilinx#(`DDR4_PRM_DCL);
	(* prefix = "" *)
	interface DDR4_Pins#(`DDR4_PRM) ddr4;
	(* prefix = "" *)
	interface VDDR4_User_Xilinx#(`DDR4_PRM) user;
endinterface

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
///
///
///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
module mkAsyncResetLong#(Integer cycles, Reset rst_in, Clock clk_out)(Reset);
	Reg#(UInt#(32)) count <- mkReg(fromInteger(cycles), clocked_by clk_out, reset_by rst_in);
	let rstifc <- mkReset(0, True, clk_out);

	rule count_down if (count > 0);
		count <= count - 1;
		rstifc.assertReset();
	endrule

	return rstifc.new_rst;
endmodule

module mkXilinxDDR4Controller#(VDDR4_Controller_Xilinx#(`DDR4_PRM) ddr4Ifc, DDR4_Configure cfg)(DDR4_Controller#(`DDR4_PRM))
	provisos( Add#(_1, 8, ddr4datasize)
			  , Add#(_2, 1, ddr4addrsize)
			  , Add#(_3, 1, ddr4besize)
			  )
	;

	if (cfg.reads_in_flight < 1)
		error("The number of reads in flight has to be at least 1");

	Integer reads = cfg.reads_in_flight;
	
	////////////////////////////////////////////////////////////////////////////////
	/// Clocks & Resets
	////////////////////////////////////////////////////////////////////////////////
	Clock													clock					  <- exposeCurrentClock;
	Reset													reset_n				  <- exposeCurrentReset;
	Reset													dly_reset_n			  <- mkAsyncResetLong( 40000, reset_n, clock );

	Clock													user_clock				= ddr4Ifc.user.clock;
	Reset													user_reset0_n		  <- mkResetInverter(ddr4Ifc.user.reset);
	Reset													user_reset_n		  <- mkAsyncReset(2, user_reset0_n, user_clock);

	////////////////////////////////////////////////////////////////////////////////
	/// Design Elements
	////////////////////////////////////////////////////////////////////////////////
	FIFO#(DDR4Request#(ddr4addrsize,
					ddr4datasize,
					ddr4besize))			  fRequest				 <- mkFIFO(clocked_by user_clock, reset_by user_reset_n);
	
	FIFO#(DDR4Response#(ddr4datasize))			fResponse			  <- mkSizedFIFO(reads, clocked_by user_clock, reset_by user_reset_n);
	// FIFO#(DDR4Response#(ddr4datasize))			fResponse			  <- mkFIFO(clocked_by user_clock, reset_by user_reset_n);
	
	// Count#(Int#(32))								  rReadsPending		 <- mkCount(0, clocked_by user_clock, reset_by user_reset_n);
	Counter#(32)										rReadsPending		  <- mkCounter(0, clocked_by user_clock, reset_by user_reset_n);

  
	PulseWire											pwAppEn				  <- mkPulseWire(clocked_by user_clock, reset_by user_reset_n);
	PulseWire											pwAppWdfWren		  <- mkPulseWire(clocked_by user_clock, reset_by user_reset_n);
	PulseWire											pwAppWdfEnd			  <- mkPulseWire(clocked_by user_clock, reset_by user_reset_n);
	
	Wire#(Bit#(3))										wAppCmd				  <- mkDWire(0, clocked_by user_clock, reset_by user_reset_n);
	Wire#(Bit#(ddr4addrsize))						wAppAddr				  <- mkDWire(0, clocked_by user_clock, reset_by user_reset_n);
	Wire#(Bit#(ddr4besize))							wAppWdfMask			  <- mkDWire('1, clocked_by user_clock, reset_by user_reset_n);
	Wire#(Bit#(ddr4datasize))						wAppWdfData			  <- mkDWire(0, clocked_by user_clock, reset_by user_reset_n);
	
	Bool initialized		 = ddr4Ifc.user.init_done;
	Bool ctrl_ready_req	 = ddr4Ifc.user.app_rdy;
	Bool write_ready_req  = ddr4Ifc.user.app_wdf_rdy;
	Bool read_data_ready  = ddr4Ifc.user.app_rd_data_valid;
	
	////////////////////////////////////////////////////////////////////////////////
	/// Rules
	////////////////////////////////////////////////////////////////////////////////
	
	(* fire_when_enabled, no_implicit_conditions *)
	rule drive_enables;
		ddr4Ifc.user.app_en(pwAppEn);
		ddr4Ifc.user.app_hi_pri(1'b0);
		ddr4Ifc.user.app_wdf_wren(pwAppWdfWren);
		ddr4Ifc.user.app_wdf_end(pwAppWdfEnd);
	endrule

	(* fire_when_enabled, no_implicit_conditions *)
	rule drive_data_signals;
		ddr4Ifc.user.app_cmd(wAppCmd);
		ddr4Ifc.user.app_addr(wAppAddr);
		ddr4Ifc.user.app_wdf_data(wAppWdfData);
		ddr4Ifc.user.app_wdf_mask(wAppWdfMask);
	endrule
	
	
	
	rule ready(initialized);
		// rule process_write_request((fRequest.first.byteen != 0) && ctrl_ready_req && write_ready_req);
		rule process_write_request((!fRequest.first.rnw) && ctrl_ready_req && write_ready_req);
			let request <- toGet(fRequest).get;
			wAppCmd <= zeroExtend(pack(request.rnw));
			wAppAddr <= request.address;
			wAppWdfData  <= request.data;
			wAppWdfMask  <= ~request.byteen;
			pwAppEn.send;
			pwAppWdfWren.send;
			pwAppWdfEnd.send;
		endrule 
		
		// rule process_read_request(fRequest.first.byteen == 0 && ctrl_ready_req && rReadsPending < fromInteger(reads));
		// rule process_read_request(fRequest.first.byteen == 0 && ctrl_ready_req);
		// rule process_read_request(fRequest.first.rnw && ctrl_ready_req );//&& rReadsPending.value < fromInteger(reads));
		rule process_read_request(fRequest.first.rnw && ctrl_ready_req && rReadsPending.value < fromInteger(reads));
			let request <- toGet(fRequest).get;
			wAppCmd <= zeroExtend(pack(request.rnw));
			wAppAddr <= request.address;
			pwAppEn.send;
			// rReadsPending.incr(1);
			rReadsPending.up;
		endrule

		rule process_read_response(read_data_ready);
		  fResponse.enq(unpack(ddr4Ifc.user.app_rd_data));
		  // rReadsPending.decr(1);
			rReadsPending.down;
		endrule
	endrule
	

	////////////////////////////////////////////////////////////////////////////////
	/// Interface Connections / Methods
	////////////////////////////////////////////////////////////////////////////////
	interface ddr4 = ddr4Ifc.ddr4;
	interface DDR4_User user;
		interface clock = user_clock;
		interface reset_n = user_reset_n;
		method init_done = initialized;
		
		method Action request(Bit#(ddr4addrsize) addr, Bit#(ddr4besize) mask, Bit#(ddr4datasize) data);
			Bool rnw = (mask == 0);
	 let req = DDR4Request {rnw: rnw, byteen: mask, address: addr, data: data };
	 fRequest.enq(req);
		endmethod

		method ActionValue#(Bit#(ddr4datasize)) read_data;
	 fResponse.deq;
	 return fResponse.first.data;
		endmethod
	endinterface
endmodule

