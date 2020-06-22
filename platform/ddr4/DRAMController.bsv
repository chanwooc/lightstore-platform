// Courtesy of Shuotao

import Clocks::*;
import DDR4Controller::*;
import DDR4Common::*;

import Shifter::*;

import FIFO::*;
import BRAMFIFO::*;
import ConnectalBramFifo::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import Counter::*;

import DRAMControllerTypes::*;

import XilinxSyncFifo::*;
import XilinxSyncFifoW748D32::*;
import XilinxSyncFifoW640D32::*;

import RWBramCore::*;

// typedef 64 MAX_OUTSTANDING_READS;

instance Connectable#(DDR4Client, DDR4_User_VCU108);
	module mkConnection#(DDR4Client cli, DDR4_User_VCU108 usr)(Empty);
		// MAX_OUTSTANDING_READS and buffer implemented in mkXilinxDDR4Controller
		rule request;
			let req <- cli.request.get();
			usr.request(req.address, req.writeen, req.datain);
		endrule

		rule response (True);
			let x <- usr.read_data;
			cli.response.put(x);
		endrule
	endmodule
endinstance

// Brings a DDR4Client from one clock domain to another.
module mkDDR4ClientSync#(DDR4Client ddr4,
	Clock sclk, Reset srst, Clock dclk, Reset drst
	) (DDR4Client);

	// Xilinx BRAM Sync FIFO for CC
	SyncFIFOIfc#(DDR4UserRequest) reqs <- mkSyncBramFifo_w748_d32(sclk, srst, dclk);
	SyncFIFOIfc#(DDR4UserData) resps <- mkSyncBramFifo_w640_d32(dclk, drst, sclk);

	mkConnection(toPut(reqs), toGet(ddr4.request));
	mkConnection(toGet(resps), toPut(ddr4.response));

	interface Get request = toGet(reqs);
	interface Put response = toPut(resps);
endmodule

interface DDR4TrafficCapture;
	interface DDR4Server ddr4Server;
	interface DDR4Client ddr4Client;
	method Tuple3#(Bit#(64), Bit#(64), Bit#(64)) status;
	method Action dumpTraffic;
	method ActionValue#(Tuple5#(Bit#(64), Bit#(64), Bool, Bit#(64), Bit#(64))) dumpResp;
endinterface

module mkDDR4TrafficCapture(DDR4TrafficCapture);
	Reg#(Bit#(10)) reqPtr <- mkReg(0);
	Reg#(Bit#(10)) respPtr <- mkReg(0);
	RWBramCore#(Bit#(10), Tuple3#(Bit#(64), DDR4UserAddr, Bool)) reqTraffic <- mkRWBramCore;
	RWBramCore#(Bit#(10), Tuple2#(Bit#(64), DDR4UserAddr)) respTraffic <- mkRWBramCore;
	FIFO#(DDR4UserAddr) readAddrQ <- mkSizedFIFO(64);
	
	FIFO#(DDR4UserRequest) reqQ <- mkFIFO;
	FIFO#(DDR4UserData) respQ <- mkFIFO;
	Reg#(Bit#(64)) cycle <- mkReg(0);
	FIFOF#(void) dumpReqQ <- mkFIFOF;
	
	Reg#(Bit#(64)) totalDRAMWrite		<- mkReg(0);
	Reg#(Bit#(64)) totalDRAMReadReq	<- mkReg(0);
	Reg#(Bit#(64)) totalDRAMReadResp <- mkReg(0);

	(* fire_when_enabled, no_implicit_conditions *)
	rule doCycle;
		cycle <= cycle + 1;
	endrule
	
	Reg#(Bit#(10)) dumpPtr <- mkReg(0);
	rule doDump if (dumpReqQ.notEmpty);
		if (dumpPtr == maxBound) dumpReqQ.deq;
		dumpPtr <= dumpPtr + 1;
		reqTraffic.rdReq(dumpPtr);
		respTraffic.rdReq(dumpPtr);
	endrule
	
	
	interface DDR4Server ddr4Server;
		interface Put request;
			method Action put(DDR4UserRequest req);
				reqTraffic.wrReq(reqPtr, tuple3(cycle, req.address, req.writeen == 0));
				reqPtr <= reqPtr + 1;
				if ( req.writeen == 0) begin
					readAddrQ.enq(req.address);
					totalDRAMReadReq <= totalDRAMReadReq + 1;
				end
				else begin
					totalDRAMWrite <= totalDRAMWrite + 1;
				end
				reqQ.enq(req);
			endmethod
		endinterface
		interface Get response = toGet(respQ);
	endinterface
	
	interface DDR4Client ddr4Client;
		interface Get request = toGet(reqQ);
		interface Put response;
			method Action put(DDR4UserData resp);
				let addr <- toGet(readAddrQ).get;
				totalDRAMReadResp <= totalDRAMReadResp + 1;
				respTraffic.wrReq(respPtr, tuple2(cycle, addr));
				respPtr <= respPtr + 1;
				respQ.enq(resp);
			endmethod
		endinterface
	endinterface

	method Tuple3#(Bit#(64), Bit#(64), Bit#(64)) status;
		return tuple3(totalDRAMWrite ,
					  totalDRAMReadReq ,
					  totalDRAMReadResp);
	endmethod
	method Action dumpTraffic;
		dumpReqQ.enq(?);
	endmethod
	method ActionValue#(Tuple5#(Bit#(64), Bit#(64), Bool, Bit#(64), Bit#(64))) dumpResp;
		let {reqCycle, reqAddr, rnw} = reqTraffic.rdResp;
		let {respCycle, respAddr} = respTraffic.rdResp;
		reqTraffic.deqRdResp;
		respTraffic.deqRdResp;
		return tuple5(reqCycle, zeroExtend(reqAddr), rnw, respCycle, zeroExtend(respAddr));
	endmethod
endmodule

