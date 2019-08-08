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
	method Action startGetPpa(Bit#(32) numKtHigh, Bit#(32) numKtLow);
	method Action startGetPpaDest(Bit#(32) num);

	// TODO: testing.. guards on getPpaHigh/getPpaLow needs to be fixed
	method ActionValue#(Bit#(32)) getPpaHigh();
	method ActionValue#(Bit#(32)) getPpaLow();
	method ActionValue#(Bit#(32)) getPpaDest();

	method Action setDmaKtPpaRef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
endinterface

module mkKtAddrManager #(
	Vector#(3, MemReadEngineServer#(DataBusWidth)) rsV
) (KtAddrManager);
	// DMA SgId for Flash Addresses (High KT, Low KT) and destination KT Flash Addresses
	// [0]: High Level, [1]: Low Level, [2]: Merged result
	Vector#(3, Reg#(Bit#(32))) dmaPpaSgid <- replicateM(mkReg(0));

	///////////////////////////////////////////////////
	// Generate read request for Ppa lists (High/Low)
	// * DMA burst/length is 128 Bytes => dmaBurstBytes
	///////////////////////////////////////////////////
	Integer dmaBurstBytes = 128;

	// [0]: High Level, [1]: Low Level, [2]: Merged result
	Vector#(3, FIFOF#(Bit#(32))) genPpaReq <- replicateM(mkFIFOF);
	Vector#(3, FIFOF#(Bit#(32))) ppaList <- replicateM(mkSizedFIFOF(4));

	for (Integer i=0; i<3; i=i+1) begin
		Reg#(Bit#(32)) ppaReqSent <- mkReg(0);
		FIFOF#(Tuple2#(Bool,Bit#(5))) dmaPpaReqToResp <- mkSizedFIFOF(2); // TODO: match ReadEngine cmdQDepth
		rule generatePpaReq;
			// each req is 8Beat=128B holding 32 Ppa entries
			// for every 32 KT Ppas, DMA req needs to be generated
			let dmaCmd = MemengineCmd {
								sglId: dmaPpaSgid[i], 
								base: zeroExtend(ppaReqSent<<7), // <<7 or *128
								len:fromInteger(dmaBurstBytes), 
								burstLen:fromInteger(dmaBurstBytes)
							};
			rsV[i].request.put(dmaCmd);

			if ( ppaReqSent < ((genPpaReq[i].first-1)>>5) /*+1 -1*/ ) begin
				ppaReqSent <= ppaReqSent + 1;

				// non-last request (= 32 LPA all valid)
				dmaPpaReqToResp.enq(tuple2(False,?)); 
			end
			else begin
				// Sending the last request @ ppaReqSent == ((genPpaReq[i].first-1)>>5)+1-1
				genPpaReq[i].deq;
				ppaReqSent <= 0;

				// last request (= 1-32 elems are valid, 32 is encoded 0)
				dmaPpaReqToResp.enq(tuple2(True, genPpaReq[i].first[4:0])); 
			end
		endrule

		// Bit#(2) to indicate # of valid elements in a word (max 4)
		// 4 is encoded 0 instead
		FIFOF#(Tuple2#(Bit#(2),Bit#(WordSz))) ppaList4Elem <- mkSizedFIFOF(8); 
		Reg#(Bit#(8)) ppaRespBeat <- mkReg(0);
		rule collectPpaResp;
			let d <- toGet(rsV[i].data).get;
			if (tpl_1(dmaPpaReqToResp.first) == False) begin
				// Not last request, so receive 8 full beats
				ppaList4Elem.enq(tuple2(2'b0, d.data));
				if (ppaRespBeat < 7) ppaRespBeat <= ppaRespBeat+1;
				else begin
					ppaRespBeat <= 0;
					dmaPpaReqToResp.deq;
				end
			end 
			else begin
				Bit#(8) numValidElem = zeroExtend(tpl_2(dmaPpaReqToResp.first)); // 0-31, and 0 encodes "32"
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
					dmaPpaReqToResp.deq;
				end
			end
		endrule

		Reg#(Bit#(2)) parsePnt <- mkReg(0);
		rule parsePpa4to1;
			let numVal = tpl_1(ppaList4Elem.first); // 0-3, 0 encodes that all 4 Ppas are valid
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

	Reg#(Bit#(32)) highPpaCnt <- mkReg(0);
	Reg#(Bit#(32)) highPpaTotal <- mkReg(0);
	Reg#(Bit#(32)) lowPpaCnt <- mkReg(0);
	Reg#(Bit#(32)) lowPpaTotal <- mkReg(0);
	Reg#(Bit#(32)) destPpaCnt <- mkReg(0);
	Reg#(Bit#(32)) destPpaTotal <- mkReg(0);

	method ActionValue#(Bit#(32)) getPpaHigh();
		highPpaCnt <= highPpaCnt + 1;
		ppaList[0].deq;
		return ppaList[0].first;
	endmethod

	method ActionValue#(Bit#(32)) getPpaLow();
		lowPpaCnt <= lowPpaCnt + 1;
		ppaList[1].deq;
		return ppaList[1].first;
	endmethod

	method ActionValue#(Bit#(32)) getPpaDest();
		destPpaCnt <= destPpaCnt + 1;
		ppaList[2].deq;
		return ppaList[2].first;
	endmethod

	method Action startGetPpa(Bit#(32) numKtHigh, Bit#(32) numKtLow) if (lowPpaCnt==lowPpaTotal && highPpaCnt==highPpaTotal);
		genPpaReq[0].enq(numKtHigh);
		genPpaReq[1].enq(numKtLow);

		highPpaCnt <= 0;
		lowPpaCnt <= 0;
		highPpaTotal <= numKtHigh;
		lowPpaTotal <= numKtLow;
	endmethod

	method Action startGetPpaDest(Bit#(32) num) if (destPpaCnt==destPpaTotal);
		genPpaReq[2].enq(num);

		destPpaCnt <= 0;
		destPpaTotal <= num;
	endmethod

	method Action setDmaKtPpaRef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
		dmaPpaSgid[0] <= sgIdHigh;
		dmaPpaSgid[1] <= sgIdLow;
		dmaPpaSgid[2] <= sgIdRes;
	endmethod
endmodule
