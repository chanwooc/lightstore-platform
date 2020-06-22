// Courtesy of Shuotao
`include "ConnectalProjectConfig.bsv"

import FIFO::*;
import Vector::*;
import DRAMController::*;
import Connectable::*;
import HostInterface::*;

// import DRAM stuff
import DDR4Common::*;
import DDR4Controller::*;

`ifdef SIMULATION
import DDR4Sim::*;
`else
import Clocks::*;
import DefaultValue::*;
`endif

import GetPut::*;
import ClientServerHelper::*;
import DRAMControllerTypes::*;


interface Top_Pins;
`ifndef SIMULATION
	interface DDR4_Pins_Dual_VCU108 pins_ddr4;
`endif
endinterface



interface Ddr4PerfRequest;
	method Action startWriteDram(Bit#(64) numCL, Bit#(32) stride);
	method Action startReadDram(Bit#(64) numCL, Bit#(32) stride);
endinterface

interface Ddr4PerfIndication;
	method Action writeDone(Bit#(32) cycles_0, Bit#(32) cycles_1);
	method Action readDone(Bit#(32) cycles_0, Bit#(32) missMatch_0, Bit#(32) cycles_1, Bit#(32) missMatch_1);
endinterface

interface Ddr4Perf;
	interface Ddr4PerfRequest request;
	interface Top_Pins pins;
endinterface


module mkDdr4Perf#(HostInterface host, Ddr4PerfIndication indication)(Ddr4Perf);
	Vector#(2,FIFO#(DDR4UserRequest)) reqs <- replicateM(mkFIFO());
	Vector#(2,FIFO#(DDR4UserData)) resps <- replicateM(mkFIFO());
	Vector#(2,DDR4Client) ddr_clients = zipWith(toClient, reqs, resps);

	`ifdef SIMULATION
	Vector#(2, DDR4_User_VCU108) ddr4_ctrl_users <- replicateM(mkDDR4Simulator);
	zipWithM_(mkConnection, ddr_clients, ddr4_ctrl_users);
	`else 
	Clock curr_clk <- exposeCurrentClock();
	Reset curr_rst_n <- exposeCurrentReset();

	// DDR4 C1
	`ifdef VirtexUltrascalePlus // vcu118
	let sys_clk1 = host.tsys_clk1_250mhz;
	`else // vcu108
	let sys_clk1 = host.tsys_clk1_300mhz;
	`endif
	let sys_rst1 <- mkAsyncResetFromCR(20, sys_clk1);

	DDR4_Controller_VCU108 ddr4_ctrl_0 <- mkDDR4Controller_VCU108(defaultValue, clocked_by sys_clk1, reset_by sys_rst1);
		
	Clock ddr4clk0 = ddr4_ctrl_0.user.clock;
	Reset ddr4rstn0 = ddr4_ctrl_0.user.reset_n;

	let ddr_cli_300mhz_0 <- mkDDR4ClientSync(ddr_clients[0], curr_clk, curr_rst_n, ddr4clk0, ddr4rstn0);
	mkConnection(ddr_cli_300mhz_0, ddr4_ctrl_0.user);

	// DDR4 C2
	`ifdef VirtexUltrascalePlus // vcu118
	let sys_clk2 = host.tsys_clk2_250mhz;
	`else
	let sys_clk2 = host.tsys_clk1_300mhz;
	`endif
	let sys_rst2 <- mkAsyncResetFromCR(20, sys_clk2);
		
	DDR4_Controller_VCU108 ddr4_ctrl_1 <- mkDDR4Controller_VCU108(defaultValue, clocked_by sys_clk2, reset_by sys_rst2);
		
	Clock ddr4clk1 = ddr4_ctrl_1.user.clock;
	Reset ddr4rstn1 = ddr4_ctrl_1.user.reset_n;
	
	let ddr_cli_300mhz_1 <- mkDDR4ClientSync(ddr_clients[1], curr_clk, curr_rst_n, ddr4clk1, ddr4rstn1);
	mkConnection(ddr_cli_300mhz_1, ddr4_ctrl_1.user);
	`endif

	Reg#(Bool) started <- mkReg(False);
	Reg#(Bit#(32)) cycleCnt <- mkReg(0);

	rule increCycle (started);
		cycleCnt <= cycleCnt + 1;
	endrule

	Vector#(2,FIFO#(Bit#(32))) cntRdMaxQ <- replicateM(mkFIFO());
	Vector#(2,FIFO#(Bit#(32))) respMaxQ <- replicateM(mkFIFO());
	Vector#(2,FIFO#(Bit#(32))) cntWrMaxQ <- replicateM(mkFIFO());

	Vector#(2,FIFO#(Tuple2#(Bit#(32),Bit#(32)))) readDoneQs <- replicateM(mkFIFO());
	Vector#(2, FIFO#(Bit#(32))) writeDoneQs <- replicateM(mkFIFO());

	Reg#(Bit#(5)) strideReg <- mkReg(0);

	for (Integer i = 0; i < 2; i = i + 1) begin
		Reg#(Bit#(32)) cntRd <- mkReg(0);
		rule doRdReq;
			let cntRdMax = cntRdMaxQ[i].first();
			$display("(%t)Read Req cntRd = %d, cntRdMax = %d", $time, cntRd, cntRdMax);
			if ( cntRd < cntRdMax ) begin
				reqs[i].enq(DDR4UserRequest{address: truncate(cntRd<<(3+strideReg)), writeen: 80'b0, datain:?});
				cntRd <= cntRd + 1;
			end
			else begin
				cntRd <= 0;
				cntRdMaxQ[i].deq();
			end
		endrule

		Reg#(Bit#(32)) respCnt <- mkReg(0);
		Reg#(Bit#(32)) missCnt <- mkReg(0);

		rule doResp;
			let respMax = respMaxQ[i].first;
			if ( respCnt < respMax ) begin
				respCnt <= respCnt + 1;
				let d <- toGet(resps[i]).get();
				if ( truncate(d) != respCnt ) begin
					missCnt <= missCnt + 1;
				end
				$display("(%t)Get Val[%d] from %d = %h", $time, respCnt, i, d);
			end
			else begin
				readDoneQs[i].enq(tuple2(cycleCnt, missCnt));
				respCnt <= 0;
				missCnt <= 0;
				respMaxQ[i].deq();
			end
		endrule


		Reg#(Bit#(32)) cntWr <- mkReg(0);

		rule doWrReq;
			let cntWrMax = cntWrMaxQ[i].first();
			$display("(%t)Write Req[%d] cntWr = %d, cntWrMax = %d", $time, i, cntWr, cntWrMax);
			if ( cntWr < cntWrMax ) begin
				reqs[i].enq(DDR4UserRequest{address: truncate(cntWr<<(3+strideReg)), writeen: -1, datain:extend(cntWr)});
				cntWr <= cntWr + 1;
			end
			else begin
				cntWr <= 0;
				cntWrMaxQ[i].deq();
				writeDoneQs[i].enq(cycleCnt);
			end
		endrule
	end

	rule doRdDone;
		let rdDone_0 <- toGet(readDoneQs[0]).get();
		let rdDone_1 <- toGet(readDoneQs[1]).get();
		indication.readDone(tpl_1(rdDone_0),tpl_2(rdDone_0),tpl_1(rdDone_1),tpl_2(rdDone_1));
	endrule

	rule doWrDone;
		let wrDone_0 <- toGet(writeDoneQs[0]).get();
		let wrDone_1 <- toGet(writeDoneQs[1]).get();
		indication.writeDone(wrDone_0,wrDone_1);
	endrule

	interface Ddr4PerfRequest request;	 
		method Action startReadDram(Bit#(64) numCL, Bit#(32) stride);
			$display("(%t)Read Req numCL = %h", $time, numCL);
			cycleCnt <= 0;
			strideReg <= truncate(stride);
			started <= True;
			cntRdMaxQ[0].enq(truncate(numCL));
			respMaxQ[0].enq(truncate(numCL));
			cntRdMaxQ[1].enq(truncate(numCL));
			respMaxQ[1].enq(truncate(numCL));
		endmethod

		method Action startWriteDram(Bit#(64) numCL, Bit#(32) stride);
			$display("(%t)Write Req numCL = %h", $time, numCL);
			cycleCnt <= 0;
			strideReg <= truncate(stride);
			started <= True;
			cntWrMaxQ[0].enq(truncate(numCL));
			cntWrMaxQ[1].enq(truncate(numCL));
		endmethod
	endinterface

	interface Top_Pins pins;		
		`ifndef SIMULATION
		interface DDR4_Pins_Dual_VCU108 pins_ddr4;
			interface pins_c0 = ddr4_ctrl_0.ddr4;
			interface pins_c1 = ddr4_ctrl_1.ddr4;
		endinterface		
		`endif
	endinterface
endmodule
