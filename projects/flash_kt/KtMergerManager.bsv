import FIFOF::*;
import FIFO::*;
import FIFOLevel::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

import Vector::*;
import List::*;

import ConnectalMemory::*;
import ConnectalConfig::*;
import ConnectalMemTypes::*;
import MemReadEngine::*;
import MemWriteEngine::*;
import Pipe::*;
import Leds::*;

import Clocks :: *;
import Xilinx       :: *;
`ifndef BSIM
import XilinxCells ::*;
`endif

import ControllerTypes::*;
import KeytableMerger::*;

interface KtMergerManager;
	method Action runMerge(Bit#(32) numKtHigh, Bit#(32) numKtLow);
	method ActionValue#(Bit#(32)) getPPA(); // TODO: for testing only.. remove later

	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
	method Action setDmaMergedKtRef(Bit#(32) sgId);
	method Action setDmaInvalPPARef(Bit#(32) sgId);

	method ActionValue#(FlashCmd) getFlashReq();
	method Action enqFlashWordRead(Tuple2#(Bit#(WordSz), TagT) taggedRdata);
	method ActionValue#(Tuple2#(Bit#(WordSz), TagT)) getFlashWordWrite();
	method Action flashWriteReq(TagT tag);
endinterface

module mkKtMergerManager #(
	Vector#(4, MemReadEngineServer#(DataBusWidth)) rs,
	Vector#(2, MemWriteEngineServer#(DataBusWidth)) ws
) (KtMergerManager);
	// Merger
	MergeKeytable merger <- mkMergeKeytable;

	// DMA SgId for Flash Addresses (High KT, Low KT) and destination KT Flash Addresses
	Reg#(Bit#(32)) dmaSgidKtHighPPA <- mkReg(0);
	Reg#(Bit#(32)) dmaSgidKtLowPPA <- mkReg(0);
	Reg#(Bit#(32)) dmaSgidKtGenPPA <- mkReg(0);

	// DMA SgID for merged KT back to Host and invalidated flash addr collected
	Reg#(Bit#(32)) dmaSgidMergedKt <- mkReg(0);
	Reg#(Bit#(32)) dmaSgidInvalPPA <- mkReg(0);

	///////////////////////////////////////////////////
	// Generate read request for PPA lists (High/Low)
	// * DMA burst/length is 128 Bytes => dmaBurstBytes
	///////////////////////////////////////////////////
	Integer dmaBurstBytes = 128;

	FIFOF#(Bit#(32)) genHighPPAReq <- mkFIFOF;
	FIFOF#(Bit#(32)) genLowPPAReq <- mkFIFOF;

	Reg#(Bit#(32)) highPPAReqSent <- mkReg(0);
	FIFOF#(Tuple2#(Bool,Bit#(5))) dmaHighPPAReqToResp <- mkSizedFIFOF(4); // TODO: match ReadEngine cmdQDepth
	rule generateHighPPAReq;
		// each req is 8Beat=128B holding 32 PPA entries
		// for every 32 KT PPAs, DMA req needs to be generated
		let dmaCmd = MemengineCmd {
							sglId: dmaSgidKtHighPPA, 
							base: zeroExtend(highPPAReqSent<<7), // <<7 or *128
							len:fromInteger(dmaBurstBytes), 
							burstLen:fromInteger(dmaBurstBytes)
						};
		rs[0].request.put(dmaCmd);

		if ( highPPAReqSent < ((genHighPPAReq.first-1)>>5) /*+1 -1*/ ) begin
			highPPAReqSent <= highPPAReqSent + 1;

			// non-last request (= 32 LPA all valid)
			dmaHighPPAReqToResp.enq(tuple2(False,?)); 
		end
		else begin
			// Sending the last request @ highPPAReqSent == ((genHighPPAReq.first-1)>>5)+1-1
			genHighPPAReq.deq;
			highPPAReqSent <= 0;

			// last request (= 1-32 elems are valid, 32 is encoded 0)
			dmaHighPPAReqToResp.enq(tuple2(True, genHighPPAReq.first[4:0])); 
		end
	endrule

	// Bit#(2) to indicate # of valid elements in a word (max 4)
	// 4 is encoded 0 instead
	FIFOF#(Tuple2#(Bit#(2),Bit#(WordSz))) highPPAList4Elem <- mkSizedFIFOF(8); 
	Reg#(Bit#(8)) highPPARespBeat <- mkReg(0);
	rule collectHighPPAResp;
		let d <- toGet(rs[0].data).get;
		if (tpl_1(dmaHighPPAReqToResp.first) == False) begin
			// Not last request, so receive 8 full beats
			highPPAList4Elem.enq(tuple2(2'b0, d.data));
			if (highPPARespBeat < 7) highPPARespBeat <= highPPARespBeat+1;
			else begin
				highPPARespBeat <= 0;
				dmaHighPPAReqToResp.deq;
			end
		end 
		else begin
			Bit#(8) numValidElem = zeroExtend(tpl_2(dmaHighPPAReqToResp.first)); // 0-31, and 0 encodes "32"
			if (numValidElem == 0) numValidElem=32;

			if ( ((highPPARespBeat+1)<<2) <= numValidElem ) begin
				highPPAList4Elem.enq(tuple2(2'b0, d.data));
			end
			else if ( (highPPARespBeat<<2) <= numValidElem ) begin
				Bit#(8) remainElem = numValidElem - ( highPPARespBeat<<2 );
				highPPAList4Elem.enq(tuple2(truncate(remainElem), d.data));
			end

			if (highPPARespBeat < 7) highPPARespBeat <= highPPARespBeat+1;
			else begin
				highPPARespBeat <= 0;
				dmaHighPPAReqToResp.deq;
			end
		end
	endrule

	FIFOF#(Bit#(32)) highPPAList <- mkSizedFIFOF(32); 
	Reg#(Bit#(2)) parseHighPnt <- mkReg(0);
	rule parseHighPPA;
		let numVal = tpl_1(highPPAList4Elem.first); // 0-3, 0 encodes that all 4 PPAs are valid
		Vector#(4, Bit#(32)) d = unpack(tpl_2(highPPAList4Elem.first));

		highPPAList.enq(pack(d[parseHighPnt]));
		if( parseHighPnt == 3 || (parseHighPnt+1 == numVal) ) begin
			parseHighPnt <= 0;
			highPPAList4Elem.deq;
		end
		else begin
			parseHighPnt <= parseHighPnt + 1;
		end
	endrule

	method ActionValue#(Bit#(32)) getPPA(); // TODO: for testing only.. remove later
		highPPAList.deq;
		return highPPAList.first;
	endmethod

	method Action runMerge(Bit#(32) numKtHigh, Bit#(32) numKtLow);
		genHighPPAReq.enq(numKtHigh);
		genLowPPAReq.enq(numKtLow);

		//merger.runMerge(numKtHigh, numKtLow);
	endmethod

	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
		dmaSgidKtHighPPA <= sgIdHigh;
		dmaSgidKtLowPPA <= sgIdLow;
		dmaSgidKtGenPPA <= sgIdRes;
	endmethod
	method Action setDmaMergedKtRef(Bit#(32) sgId);
		dmaSgidMergedKt <= sgId;
	endmethod
	method Action setDmaInvalPPARef(Bit#(32) sgId);
		dmaSgidInvalPPA <= sgId;
	endmethod
endmodule
