import FIFO::*;
import FIFOF::*;
import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;
import ConnectalXilinxCells::*;

import AuroraCommon::*;
import AuroraGearbox::*;

interface AuroraIfc;
	method Action send(DataIfc data, PacketType ptype);
	method ActionValue#(Tuple2#(DataIfc, PacketType)) receive;
	method Tuple4#(Bit#(32), Bit#(32), Bit#(32), Bit#(32)) getDebugCnts;

	interface Clock clk;
	interface Reset rst;

	interface AuroraStatus#(4) status;

	(* prefix = "" *)
	interface Aurora_Pins#(4) aurora;
endinterface

(* synthesize *)
module mkAuroraIntra1#(Clock gt_clk_p, Clock gt_clk_n, Clock clk110, Reset rst110) (AuroraIfc);
	Clock cur_clk <- exposeCurrentClock;
	Reset cur_rst <- exposeCurrentReset;

`ifndef BSIM
	let fmc1_gt_clk_i <- mkClockIBUFDS_GTE(
`ifdef ClockDefaultParam
						   defaultValue,
`endif
						   True, gt_clk_p, gt_clk_n);

	// init_clk is configured to match the frequency of user_clk (110MHz) for Ultrascale designs
	//  vc707 (7-series) can also allows 110 MHz init clock frequency
	Clock init_clk_i = clk110;

	Reset system_rst <- mkAsyncReset(16, cur_rst, init_clk_i);  // system reset should be min 6 user_clk(110MHz) cycles
	MakeResetIfc gt_rst_ifc <- mkReset(8, True, init_clk_i); // gt_reset should be min 6 init_clk cycles
	Reset gt_rst = gt_rst_ifc.new_rst;
	AuroraImportIfc#(4) auroraIntraImport <- mkAuroraImport_8b10b_fmc1(fmc1_gt_clk_i.gen_clk, init_clk_i, system_rst, gt_rst);
`else
	AuroraImportIfc#(4) auroraIntraImport <- mkAuroraImport_8b10b_bsim;
`endif

	Clock aclk = auroraIntraImport.aurora_clk;
	Reset arst = auroraIntraImport.aurora_rst;

	Reg#(Bit#(32)) gearboxSendCnt <- mkReg(0);
	Reg#(Bit#(32)) gearboxRecCnt <- mkReg(0);
	Reg#(Bit#(32)) auroraSendCnt <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(32)) auroraRecCnt <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(32)) auroraSendCntCC <- mkSyncRegToCC(0, aclk, arst);
	Reg#(Bit#(32)) auroraRecCntCC <- mkSyncRegToCC(0, aclk, arst);
	rule syncCnt;
		auroraSendCntCC <= auroraSendCnt;
		auroraRecCntCC <= auroraRecCnt;
	endrule


	AuroraGearboxIfc auroraGearbox <- mkAuroraGearbox(aclk, arst);
	rule auroraOut if (auroraIntraImport.user.status.channel_up==1);
		let d <- auroraGearbox.auroraSend;
		$display("Gearbox send out: %x", d);
		auroraSendCnt <= auroraSendCnt + 1;
		auroraIntraImport.user.send(d);
	endrule
	/*
	rule resetDeadLink ( auroraIntraImport.user.status.channel_up == 0 );
		auroraGearbox.resetLink;
		$display("Gearbox reset link");
	endrule
	*/
	rule auroraIn;
		let d <- auroraIntraImport.user.receive;
		$display("Gearbox received: %x", d);
		auroraRecCnt <= auroraRecCnt + 1;
		auroraGearbox.auroraRecv(d);
	endrule
		

	method Tuple4#(Bit#(32), Bit#(32), Bit#(32), Bit#(32)) getDebugCnts;
		return tuple4(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC);
	endmethod


	method Action send(DataIfc data, PacketType ptype);
		auroraGearbox.send(data, ptype);
		gearboxSendCnt <= gearboxSendCnt + 1;
	endmethod
	method ActionValue#(Tuple2#(DataIfc, PacketType)) receive;
		let d <- auroraGearbox.recv;
		gearboxRecCnt <= gearboxRecCnt + 1;
		return d;
	endmethod

	interface AuroraStatus status = auroraIntraImport.user.status;

	interface Clock clk = auroraIntraImport.aurora_clk;
	interface Reset rst = auroraIntraImport.aurora_rst;

	interface Aurora_Pins aurora = auroraIntraImport.aurora;
endmodule

module mkAuroraImport_8b10b_bsim (AuroraImportIfc#(4));
	Clock clk <- exposeCurrentClock;
	Reset rst <- exposeCurrentReset;

	FIFOF#(Bit#(128)) mirrorQ <- mkSizedFIFOF(2);
	Reg#(Bit#(1)) laneUpR <- mkReg(0);
	Reg#(Bit#(32)) laneUpDelay <- mkReg(500);

	rule updateLaneUp;
		if (laneUpDelay ==0) begin
			laneUpR <= 1;
		end
		else begin
			laneUpDelay <= laneUpDelay - 1;
		end
	endrule


	rule detectFull if (!mirrorQ.notFull);
		$display("WARNING: mirrorQ is full!");
	endrule

	interface aurora_clk = clk;
	interface aurora_rst = rst;
	interface AuroraUserIfc user;
		interface AuroraStatus status;
			method Bit#(1) channel_up = laneUpR;
			method Bit#(4) lane_up = signExtend(laneUpR);
			method Bit#(1) hard_err = 0;
			method Bit#(1) soft_err = 0;
			method Bit#(8) data_err_count = 0;
		endinterface

		method Action send(Bit#(128) data);
			mirrorQ.enq(data);
		endmethod

		method ActionValue#(Bit#(128)) receive;
			mirrorQ.deq;
			return mirrorQ.first;
		endmethod
	endinterface
endmodule

import "BVI" aurora_8b10b_fmc1_exdes =
module mkAuroraImport_8b10b_fmc1#(Clock gt_clk_in, Clock init_clk, Reset init_rst_n, Reset gt_rst_n) (AuroraImportIfc#(4));
	default_clock no_clock;
	default_reset no_reset;

	input_clock (INIT_CLK_IN) = init_clk;
	input_reset (RESET_N) = init_rst_n;     // Bluespec Reset is Active Low (mapped to RESET_N)
	input_reset (GT_RESET_N) = gt_rst_n;

	output_clock aurora_clk(USER_CLK);
	output_reset aurora_rst(USER_RST_N) clocked_by (aurora_clk);

	input_clock (GT_REFCLK) = gt_clk_in;

	input_clock clk() <- exposeCurrentClock;

	interface Aurora_Pins aurora;
		method rxn_in(RXN) enable((*inhigh*) rx_n_en) clocked_by(clk); // Action method requires a clock domain
		method rxp_in(RXP) enable((*inhigh*) rx_p_en) clocked_by(clk);
		method TXN txn_out(); 
		method TXP txp_out();
	endinterface

	interface AuroraUserIfc user;
		interface AuroraStatus status;
			method CHANNEL_UP channel_up();
			method LANE_UP lane_up();
			method HARD_ERR hard_err();
			method SOFT_ERR soft_err();
			method ERR_COUNT data_err_count();
		endinterface

		method send(TX_DATA) enable(tx_en) ready(tx_rdy) clocked_by(aurora_clk) reset_by(aurora_rst);
		method RX_DATA receive() enable((*inhigh*) rx_en) ready(rx_rdy) clocked_by(aurora_clk) reset_by(aurora_rst);
	endinterface
	
/*
	schedule (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count) CF 
	(aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);
	schedule (user_send) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);

	schedule (user_receive) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);

	schedule (user_receive) SB (user_send);
	schedule (user_send) C (user_send);
	schedule (user_receive) C (user_receive);
*/
	schedule (aurora_txn_out, aurora_txp_out, user_status_channel_up, user_status_lane_up, user_status_hard_err, user_status_soft_err, user_status_data_err_count) CF 
	(aurora_txn_out, aurora_txp_out, user_status_channel_up, user_status_lane_up, user_status_hard_err, user_status_soft_err, user_status_data_err_count);

	schedule (aurora_rxn_in) CF (aurora_txn_out, aurora_txp_out, user_status_channel_up, user_status_lane_up, user_status_hard_err, user_status_soft_err, user_status_data_err_count);
	schedule (aurora_rxp_in) CF (aurora_txn_out, aurora_txp_out, user_status_channel_up, user_status_lane_up, user_status_hard_err, user_status_soft_err, user_status_data_err_count);

	schedule (user_send) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_status_channel_up, user_status_lane_up, user_status_hard_err, user_status_soft_err, user_status_data_err_count);
	schedule (user_receive) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_status_channel_up, user_status_lane_up, user_status_hard_err, user_status_soft_err, user_status_data_err_count);

	schedule (aurora_rxn_in) C (aurora_rxn_in);
	schedule (aurora_rxp_in) C (aurora_rxp_in);
	schedule (aurora_rxn_in) CF (aurora_rxp_in);

	schedule (user_receive) CF (user_send);
	schedule (user_send) C (user_send);
	schedule (user_receive) C (user_receive);
endmodule
