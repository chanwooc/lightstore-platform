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
import KtAddrManager::*;

import FlashCtrlIfc::*;

// LightStore Keytable Merge Manager
interface LightStoreKtMerger;
	method Action startCompaction(Bit#(32) numKtHigh, Bit#(32) numKtLow);
	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
	method Action setDmaKtOutputRef(Bit#(32) sgIdKtBuf, Bit#(32) sgIdInvalPPA);

	method ActionValue#(Tuple2#(Bit#(32), Bit#(64))) mergeDone;

// FIXME: below are methods for testing
//	method ActionValue#(Tuple5#(Bit#(32), Bit#(32), Bit#(32), Bit#(32), Bit#(32))) pageReadIssued;
//	method ActionValue#(Tuple6#(Bit#(1),Bit#(32),Bit#(32),Bit#(32),Bit#(32),Bit#(32))) pageConsumed;
//	method ActionValue#(Bit#(32)) getPPAHigh();
//	method ActionValue#(Bit#(32)) getPPALow();
endinterface

module mkLightStoreKtMerger #(
	Vector#(4, MemReadEngineServer#(DataBusWidth)) rs,
	Vector#(4, MemWriteEngineServer#(DataBusWidth)) ws,
	Vector#(2, Server#(DualFlashAddr, Bit#(128))) flashRs
) (LightStoreKtMerger);

	KtAddrManager addrManager <- mkKtAddrManager(rs);
	KeytableMerger ktMerger <- mkKeytableMerger;

	Reg#(Bit#(32)) mergedKtBufSgid <- mkReg(0);
	Reg#(Bit#(32)) invalPPAListSgid <- mkReg(0);

	// FIXME: below are FIFOs for testing
	//FIFOF#(Tuple5#(Bit#(32), Bit#(32), Bit#(32), Bit#(32), Bit#(32))) genFlashRead <- mkFIFOF;
	//FIFOF#(Tuple6#(Bit#(1),Bit#(32),Bit#(32),Bit#(32),Bit#(32),Bit#(32))) genPageConsumed <- mkFIFOF;

	rule driveReadFlashPPAHigh;
		let ppa <- addrManager.getPPAHigh;
		let d = toDualFlashAddr(ppa);
		flashRs[0].request.put(d);
		//genFlashRead.enq(tuple5(ppa, extend(d.bus), extend(d.chip), extend(d.block), extend(d.page)));
	endrule

	rule driveReadFlashPPALow;
		let ppa <- addrManager.getPPALow;
		let d = toDualFlashAddr(ppa);
		flashRs[1].request.put(d);
		//genFlashRead.enq(tuple5(ppa, extend(d.bus), extend(d.chip), extend(d.block), extend(d.page)));
	endrule

	Integer dmaBurstBytes = 128;
	Integer dmaBurstWords = dmaBurstBytes/wordBytes; //128/16 = 8
	Integer wordsPer8192Page=8192/wordBytes; // 512

	Reg#(Bit#(10)) ktHighBeatCnt <- mkReg(0);
	Reg#(Bit#(32)) genPageCntHigh <- mkReg(0);
	rule driveKtHighLvl;
		let d <- flashRs[0].response.get();

		// drop 32B
		if (ktHighBeatCnt < fromInteger(wordsPer8192Page)) begin
			ktMerger.enqHighLevelKt(d);
		end

		if (ktHighBeatCnt < fromInteger(pageWords-1)) begin
			ktHighBeatCnt <= ktHighBeatCnt+1;
		end
		else begin
			ktHighBeatCnt <= 0;
			//genPageConsumed.enq(
			//	unpack({1'b0, genPageCntHigh, pack(ktMerger.mergerDebug)})
			//	);
			genPageCntHigh <= genPageCntHigh + 1;
		end
	endrule

	Reg#(Bit#(10)) ktLowBeatCnt <- mkReg(0);
	Reg#(Bit#(32)) genPageCntLow <- mkReg(0);
	rule driveKtLowLvl;
		let d <- flashRs[1].response.get();

		// drop 32B
		if (ktLowBeatCnt < fromInteger(wordsPer8192Page)) begin
			ktMerger.enqLowLevelKt(d);
		end

		if (ktLowBeatCnt < fromInteger(pageWords-1)) begin
			ktLowBeatCnt <= ktLowBeatCnt+1;
		end
		else begin
			ktLowBeatCnt <= 0;
			//genPageConsumed.enq(
			//	unpack({1'b1, genPageCntLow, pack(ktMerger.mergerDebug)})
			//	);
			genPageCntLow <= genPageCntLow + 1;
		end
	endrule

	Reg#(Bit#(32)) mergerOutputCnt <- mkReg(0);
	Reg#(Bit#(2)) phase1 <- mkReg(0);
	Vector#(4, FIFO#(Tuple2#(Bool,Bit#(128)))) dmaWriteOut <- replicateM(mkSizedBRAMFIFO(512));
	FIFO#(Bool) dmaWriteReqQ <- mkFIFO;
	Vector#(4, FIFO#(Bool)) dmaWriteReqToRespQ <- replicateM(mkSizedFIFO(8));

	rule getMergedKeytable;
		//ktMerger.getCollectedAddr();
		let d <- ktMerger.getMergedKt();

		let last = tpl_1(d);
		let data = tpl_2(d);
		dmaWriteOut[phase1].enq(d);

		mergerOutputCnt <= mergerOutputCnt + 1;
		Bit#(9) beatTruncate = truncate(mergerOutputCnt);

		if (beatTruncate == 0) begin
			dmaWriteReqQ.enq(last);
		end

		if (beatTruncate == 511) begin
			if(last) phase1 <= 0;
			else phase1<=phase1+1;
		end
	endrule

	FIFO#(Bool) ktLastPageTrig <- mkFIFO;
	Reg#(Bit#(32)) ktResultReqSent <- mkReg(0);
	Reg#(Bit#(2)) phase2 <- mkReg(0);
	Integer keytableSizeLog = 13; // 8KB => 2^13 Byte
	rule genDmaWReq;
		dmaWriteReqQ.deq;
		let dmaCmd = MemengineCmd {
			sglId: mergedKtBufSgid,
			base: (ktResultReqSent<<keytableSizeLog),
			len: fromInteger(keytableBytes),
			burstLen: fromInteger(dmaBurstBytes)
		};
		ws[phase2].request.put(dmaCmd);

		dmaWriteReqToRespQ[phase2].enq(False);

		if(!dmaWriteReqQ.first) begin
			ktResultReqSent <= ktResultReqSent + 1;
			phase2 <= phase2 + 1;
		end
		else begin
			ktResultReqSent <= 0;
			phase2 <= 0;
			ktLastPageTrig.enq(?);
		end
	endrule

	rule trigLastPage;
		ktLastPageTrig.deq;
		dmaWriteReqToRespQ[0].enq(True);
		dmaWriteReqToRespQ[1].enq(True);
		dmaWriteReqToRespQ[2].enq(True);
		dmaWriteReqToRespQ[3].enq(True);
	endrule

	for (int i=0; i<4; i=i+1) begin
		rule sendDmaWriteData;
			dmaWriteOut[i].deq;
			let d = dmaWriteOut[i].first;
			ws[i].data.enq(tpl_2(d));
		endrule
	end

	Reg#(Bit#(64)) counter <- mkReg(0);
	Reg#(Bit#(64)) counter_firstOut <- mkReg(0);
	(* fire_when_enabled *)
	rule cntUp;
		counter <= counter+1;
	endrule

	Vector#(4,FIFO#(Bit#(32))) ktGeneratedDone <- replicateM(mkFIFO);
	for (int i=0; i<4; i=i+1) begin
		Reg#(Bit#(32)) ktGenerated <- mkReg(0);
		rule dmaWriteGetResponse;
			dmaWriteReqToRespQ[i].deq;
			if (!dmaWriteReqToRespQ[i].first) begin
				let dummy <- ws[i].done.get;
				ktGenerated <= ktGenerated + 1;

				if (i==0) begin
					if(ktGenerated==0) 
						counter_firstOut <= counter;
				end
			end
			else begin
				ktGeneratedDone[i].enq(ktGenerated);
				ktGenerated <= 0;
			end
		endrule
	end

	FIFO#(Tuple2#(Bit#(32), Bit#(64))) mergeDoneQ <- mkFIFO;
	rule indMergeDone;
		Bit#(32) d = 0;
		for (Integer i=0; i<4; i=i+1) begin
			d = d + ktGeneratedDone[i].first;
			ktGeneratedDone[i].deq;
		end

		mergeDoneQ.enq(tuple2(d, counter-counter_firstOut));
	endrule

	method Action startCompaction(Bit#(32) numKtHigh, Bit#(32) numKtLow);
		addrManager.startGetPPA(numKtHigh, numKtLow);
		ktMerger.runMerge(numKtHigh, numKtLow);

		genPageCntHigh <= 0;
		genPageCntLow <= 0;
	endmethod
	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
		addrManager.setDmaKtPPARef(sgIdHigh, sgIdLow, sgIdRes);
	endmethod
	method Action setDmaKtOutputRef(Bit#(32) sgIdKtBuf, Bit#(32) sgIdInvalPPA);
		mergedKtBufSgid <= sgIdKtBuf;
		invalPPAListSgid <= sgIdInvalPPA;
	endmethod
	method ActionValue#(Tuple2#(Bit#(32), Bit#(64))) mergeDone;
		let d <- toGet(mergeDoneQ).get;
		return d;
	endmethod

// FIXME: below are methods for testing
//	method ActionValue#(Tuple5#(Bit#(32), Bit#(32), Bit#(32), Bit#(32), Bit#(32))) pageReadIssued;
//		let d <- toGet(genFlashRead).get;
//		return d;
//	endmethod
//	method ActionValue#(Tuple6#(Bit#(1),Bit#(32),Bit#(32),Bit#(32),Bit#(32),Bit#(32))) pageConsumed;
//		let d <- toGet(genPageConsumed).get;
//		return d;
//	endmethod
//	method ActionValue#(Bit#(32)) getPPAHigh();
//		let d <- addrManager.getPPAHigh;
//		return d;
//	endmethod
//	method ActionValue#(Bit#(32)) getPPALow();
//		let d <- addrManager.getPPALow;
//		return d;
//	endmethod
endmodule
