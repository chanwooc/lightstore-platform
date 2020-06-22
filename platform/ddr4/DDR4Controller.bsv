////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2014  Bluespec, Inc.	ALL RIGHTS RESERVED.
////////////////////////////////////////////////////////////////////////////////
//  Filename		: XilinxVCU108DDR4.bsv
//  Description	: 
////////////////////////////////////////////////////////////////////////////////

// Notes : Modified by Shoutao and Chanwoo

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import Connectable ::*;
import Clocks ::*;
import FIFO ::*;
import FIFOF ::*;
import SpecialFIFOs ::*;
import TriState ::*;
import Vector ::*;
import DefaultValue ::*;
import Counter ::*;
import CommitIfc ::*;
import Memory ::*;
import ClientServer ::*;
import GetPut ::*;
import BUtils ::*;
import I2C ::*;
import StmtFSM ::*;
import DDR4Common ::*;

import XilinxCells ::*;

////////////////////////////////////////////////////////////////////////////////
/// Exports
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
/// Types
////////////////////////////////////////////////////////////////////////////////

`define DDR4_VCU108 28, 640, 80, 17, 15, 2, 1, 1, 1, 1, 1, 10, 1, 1, 80, 10, 10

typedef DDR4_Pins#(`DDR4_VCU108) DDR4_Pins_VCU108;
typedef DDR4_User#(`DDR4_VCU108) DDR4_User_VCU108;
typedef DDR4_Controller#(`DDR4_VCU108) DDR4_Controller_VCU108;
typedef VDDR4_User_Xilinx#(`DDR4_VCU108) VDDR4_User_Xilinx_VCU108;
typedef VDDR4_Controller_Xilinx#(`DDR4_VCU108) VDDR4_Controller_Xilinx_VCU108;

interface DDR4_Pins_Dual_VCU108;
	(* prefix = "c0" *)
	interface DDR4_Pins_VCU108 pins_c0;
	(* prefix = "c1" *)
	interface DDR4_Pins_VCU108 pins_c1;
endinterface

interface DDR4_Pins_Single_VCU108;
	(* prefix = "c0" *)
	interface DDR4_Pins_VCU108 pins_c0;
endinterface



////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
///
/// Implementation
///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
`ifndef BRC
import "BVI" ddr4_wrapper =
`else
import "BVI" ddr4_brc_wrapper =
`endif
module vMkVCU108DDR4Controller#(DDR4_Configure cfg)(VDDR4_Controller_Xilinx_VCU108);
	default_clock clk(c0_sys_clk_i);
	default_reset rst(sys_rst);

	interface DDR4_Pins ddr4;
		method c0_ddr4_act_n act_n clocked_by(no_clock)  reset_by(no_reset);
		method c0_ddr4_adr adr clocked_by(no_clock)	reset_by(no_reset);
		method c0_ddr4_ba ba clocked_by(no_clock)  reset_by(no_reset);
		method c0_ddr4_bg bg clocked_by(no_clock)  reset_by(no_reset);
		method c0_ddr4_cke cke clocked_by(no_clock)	reset_by(no_reset);
		method c0_ddr4_odt odt clocked_by(no_clock)	reset_by(no_reset);
		method c0_ddr4_cs_n cs_n clocked_by(no_clock)  reset_by(no_reset);
		method c0_ddr4_ck_t ck_t clocked_by(no_clock)  reset_by(no_reset);
		method c0_ddr4_ck_c ck_c clocked_by(no_clock)  reset_by(no_reset);
		method c0_ddr4_reset_n reset_n clocked_by(no_clock)  reset_by(no_reset);
		ifc_inout dm_dbi_n(c0_ddr4_dm_dbi_n) clocked_by(no_clock)  reset_by(no_reset);
		ifc_inout dq(c0_ddr4_dq) clocked_by(no_clock)  reset_by(no_reset);
		ifc_inout dqs_c(c0_ddr4_dqs_c) clocked_by(no_clock)  reset_by(no_reset);
		ifc_inout dqs_t(c0_ddr4_dqs_t) clocked_by(no_clock)  reset_by(no_reset);
	endinterface

	interface VDDR4_User_Xilinx user;
		output_clock	 clock(c0_ddr4_ui_clk);
		output_reset	 reset(c0_ddr4_ui_clk_sync_rst);
		method c0_init_calib_complete		  init_done		clocked_by(no_clock) reset_by(no_reset);
		method							app_addr(c0_ddr4_app_addr) enable((*inhigh*)en0) clocked_by(user_clock) reset_by(no_reset);
		method								  app_cmd(c0_ddr4_app_cmd)   enable((*inhigh*)en00) clocked_by(user_clock) reset_by(no_reset);
		method							app_en(c0_ddr4_app_en)		enable((*inhigh*)en1) clocked_by(user_clock) reset_by(no_reset);
		method								  app_hi_pri(c0_ddr4_app_hi_pri)		 enable((*inhigh*)en11) clocked_by(user_clock) reset_by(no_reset);
		method							app_wdf_data(c0_ddr4_app_wdf_data) enable((*inhigh*)en2) clocked_by(user_clock) reset_by(no_reset);
		method							app_wdf_end(c0_ddr4_app_wdf_end)   enable((*inhigh*)en3) clocked_by(user_clock) reset_by(no_reset);
		method							app_wdf_mask(c0_ddr4_app_wdf_mask) enable((*inhigh*)en4) clocked_by(user_clock) reset_by(no_reset);
		method							app_wdf_wren(c0_ddr4_app_wdf_wren) enable((*inhigh*)en5) clocked_by(user_clock) reset_by(no_reset);
		method c0_ddr4_app_rd_data					 app_rd_data clocked_by(user_clock) reset_by(no_reset);
		method c0_ddr4_app_rd_data_end			 app_rd_data_end clocked_by(user_clock) reset_by(no_reset);
		method c0_ddr4_app_rd_data_valid			 app_rd_data_valid clocked_by(user_clock) reset_by(no_reset);
		method c0_ddr4_app_rdy						 app_rdy clocked_by(user_clock) reset_by(no_reset);
		method c0_ddr4_app_wdf_rdy					 app_wdf_rdy clocked_by(user_clock) reset_by(no_reset);
	endinterface

	schedule
	(ddr4_act_n, ddr4_adr, ddr4_ba, ddr4_bg, ddr4_cke, ddr4_odt,
	 ddr4_cs_n, ddr4_ck_t, ddr4_ck_c, ddr4_reset_n,
	 user_init_done
	 )
	CF
	(ddr4_act_n, ddr4_adr, ddr4_ba, ddr4_bg, ddr4_cke, ddr4_odt,
	 ddr4_cs_n, ddr4_ck_t, ddr4_ck_c, ddr4_reset_n,
	 user_init_done
	 );

	schedule 
	(
	 user_app_addr, user_app_en, user_app_hi_pri, user_app_wdf_data, user_app_wdf_end, user_app_wdf_mask, user_app_wdf_wren, user_app_rd_data, 
	 user_app_rd_data_end, user_app_rd_data_valid, user_app_rdy, user_app_wdf_rdy, user_app_cmd
	 )
	CF
	(
	 user_app_addr, user_app_en, user_app_hi_pri, user_app_wdf_data, user_app_wdf_end, user_app_wdf_mask, user_app_wdf_wren, user_app_rd_data, 
	 user_app_rd_data_end, user_app_rd_data_valid, user_app_rdy, user_app_wdf_rdy, user_app_cmd
	 );
endmodule

module mkDDR4Controller_VCU108#(DDR4_Configure cfg)(DDR4_Controller_VCU108);
	(* hide_all *)
	let _v <- vMkVCU108DDR4Controller(cfg);
	let _m <- mkXilinxDDR4Controller(_v, cfg);
	return _m;
endmodule

