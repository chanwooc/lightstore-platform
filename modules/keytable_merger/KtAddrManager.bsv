import DefaultValue::*;
import FIFOF::*;
import FIFO::*;
import FIFOLevel::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

import Vector::*;
import BuildVector::*;
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

interface KtAddrManager;
	method Action startGetPPA(Bit#(32) numKtHigh, Bit#(32) numKtLow);
	// TODO: testing.. guards on getPPAHigh/getPPALow needs to be fixed
	method ActionValue#(Bit#(32)) getPPAHigh();
	method ActionValue#(Bit#(32)) getPPALow();
	method ActionValue#(Bit#(32)) getPPARes();

	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
endinterface

module mkKtAddrManager #(
	Vector#(4, MemReadEngineServer#(DataBusWidth)) rs
) (KtAddrManager);
	// DMA SgId for Flash Addresses (High KT, Low KT) and destination KT Flash Addresses
	// [0]: High Level, [1]: Low Level, [2]: Merged result
	Vector#(3, Reg#(Bit#(32))) dmaPPASgid <- replicateM(mkReg(0));

	///////////////////////////////////////////////////
	// Generate read request for PPA lists (High/Low)
	// * DMA burst/length is 128 Bytes => dmaBurstBytes
	///////////////////////////////////////////////////
	Integer dmaBurstBytes = 128;

	// [0]: High Level, [1]: Low Level, [2]: Merged result
	Vector#(3, FIFOF#(Bit#(32))) genPPAReq <- replicateM(mkFIFOF);
	Vector#(3, FIFOF#(Bit#(32))) ppaList <- replicateM(mkSizedFIFOF(32)); 

	for (Integer i=0; i<3; i=i+1) begin
		Reg#(Bit#(32)) ppaReqSent <- mkReg(0);
		FIFOF#(Tuple2#(Bool,Bit#(5))) dmaPPAReqToResp <- mkSizedFIFOF(4); // TODO: match ReadEngine cmdQDepth
		rule generatePPAReq;
			// each req is 8Beat=128B holding 32 PPA entries
			// for every 32 KT PPAs, DMA req needs to be generated
			let dmaCmd = MemengineCmd {
								sglId: dmaPPASgid[i], 
								base: zeroExtend(ppaReqSent<<7), // <<7 or *128
								len:fromInteger(dmaBurstBytes), 
								burstLen:fromInteger(dmaBurstBytes)
							};
			rs[i].request.put(dmaCmd);

			if ( ppaReqSent < ((genPPAReq[i].first-1)>>5) /*+1 -1*/ ) begin
				ppaReqSent <= ppaReqSent + 1;

				// non-last request (= 32 LPA all valid)
				dmaPPAReqToResp.enq(tuple2(False,?)); 
			end
			else begin
				// Sending the last request @ ppaReqSent == ((genPPAReq[i].first-1)>>5)+1-1
				genPPAReq[i].deq;
				ppaReqSent <= 0;

				// last request (= 1-32 elems are valid, 32 is encoded 0)
				dmaPPAReqToResp.enq(tuple2(True, genPPAReq[i].first[4:0])); 
			end
		endrule

		// Bit#(2) to indicate # of valid elements in a word (max 4)
		// 4 is encoded 0 instead
		FIFOF#(Tuple2#(Bit#(2),Bit#(WordSz))) ppaList4Elem <- mkSizedFIFOF(8); 
		Reg#(Bit#(8)) ppaRespBeat <- mkReg(0);
		rule collectPPAResp;
			let d <- toGet(rs[i].data).get;
			if (tpl_1(dmaPPAReqToResp.first) == False) begin
				// Not last request, so receive 8 full beats
				ppaList4Elem.enq(tuple2(2'b0, d.data));
				if (ppaRespBeat < 7) ppaRespBeat <= ppaRespBeat+1;
				else begin
					ppaRespBeat <= 0;
					dmaPPAReqToResp.deq;
				end
			end 
			else begin
				Bit#(8) numValidElem = zeroExtend(tpl_2(dmaPPAReqToResp.first)); // 0-31, and 0 encodes "32"
				if (numValidElem == 0) numValidElem=32;

				if ( ((ppaRespBeat+1)<<2) < numValidElem ) begin
					ppaList4Elem.enq(tuple2(2'b0, d.data));
				end
				else if ( (ppaRespBeat<<2) < numValidElem ) begin
					Bit#(8) remainElem = numValidElem - ( ppaRespBeat<<2 );
					ppaList4Elem.enq(tuple2(truncate(remainElem), d.data));
				end

				if (ppaRespBeat < 7) ppaRespBeat <= ppaRespBeat+1;
				else begin
					ppaRespBeat <= 0;
					dmaPPAReqToResp.deq;
				end
			end
		endrule

		Reg#(Bit#(2)) parsePnt <- mkReg(0);
		rule parsePPA4to1;
			let numVal = tpl_1(ppaList4Elem.first); // 0-3, 0 encodes that all 4 PPAs are valid
			Vector#(4, Bit#(32)) d = unpack(tpl_2(ppaList4Elem.first));

			ppaList[i].enq(pack(d[parsePnt]));
			if( parsePnt == 3 || (parsePnt+1 == numVal) ) begin
				parsePnt <= 0;
				ppaList4Elem.deq;
			end
			else begin
				parsePnt <= parsePnt + 1;
			end
		endrule
	end

	/////////////////////////////////////
	// Interface
	/////////////////////////////////////

	Reg#(Bit#(32)) highPPACnt <- mkReg(0);
	Reg#(Bit#(32)) highPPATotal <- mkReg(0);

	Reg#(Bit#(32)) lowPPACnt <- mkReg(0);
	Reg#(Bit#(32)) lowPPATotal <- mkReg(0);
	method ActionValue#(Bit#(32)) getPPAHigh() if( lowPPACnt == lowPPATotal || lowPPACnt > highPPACnt || (highPPACnt-lowPPACnt) < 16 );
		highPPACnt <= highPPACnt + 1;
		ppaList[0].deq;
		return ppaList[0].first;
	endmethod

	method ActionValue#(Bit#(32)) getPPALow() if ( highPPACnt == highPPATotal || lowPPACnt < highPPACnt || (lowPPACnt-highPPACnt) < 16 ); // TODO: for testing only.. remove later
		lowPPACnt <= lowPPACnt + 1;
		ppaList[1].deq;
		return ppaList[1].first;
	endmethod

	method ActionValue#(Bit#(32)) getPPARes(); // TODO: for testing only.. remove later
		ppaList[2].deq;
		return ppaList[2].first;
	endmethod

	method Action startGetPPA(Bit#(32) numKtHigh, Bit#(32) numKtLow);
		genPPAReq[0].enq(numKtHigh);
		genPPAReq[1].enq(numKtLow);
		//genPPAReq[2].enq(numKtHigh+numKtLow); // ppa to write back merged KT

		highPPACnt <= 0;
		lowPPACnt <= 0;
		highPPATotal <= numKtHigh;
		lowPPATotal <= numKtLow;
	endmethod

	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
		dmaPPASgid[0] <= sgIdHigh;
		dmaPPASgid[1] <= sgIdLow;
		dmaPPASgid[2] <= sgIdRes;
	endmethod
endmodule
