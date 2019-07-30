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

import ControllerTypes::*;
import KeytableMerger::*;

interface KtRequest;
	method Action runMerge(Bit#(32) numKtHigh, Bit#(32) numKtLow);
	method Action echoSecret(Bit#(32) dummy);

	method Action setKtHighRef(Bit#(32) sgId);
	method Action setKtLowRef(Bit#(32) sgId);
	method Action setResultRef(Bit#(32) sgId);
	method Action setCollectedAddrRef(Bit#(32) sgId);
endinterface

interface KtIndication;
	method Action mergeDone(Bit#(32) numGenKt, Bit#(64) counter);
	method Action echoBack(Bit#(32) magic);
endinterface

// Each KT is 8192
// KeytableBytes, KeytableWords = 8192, 512 (Type)
// keytableBytes, keytableWords = 8192, 512 (Integer)
Integer keytableSizeLog = 13; // 8KB => 2^13 Byte

typedef 128 DmaBurstBytes; 
Integer dmaBurstBytes = valueOf(DmaBurstBytes);
Integer dmaBurstWords = dmaBurstBytes/wordBytes; //128/16 = 8

interface MainIfc;
	interface KtRequest request;
	interface Vector#(NumWriteClients, MemWriteClient#(DataBusWidth)) dmaWriteClient;
	interface Vector#(NumReadClients, MemReadClient#(DataBusWidth)) dmaReadClient;
endinterface

module mkMain#(Clock derivedClock, Reset derivedReset, KtIndication indication)(MainIfc);
	MergeKeytable merger <- mkMergeKeytable;

	Vector#(NumReadClients, MemReadEngine#(DataBusWidth, DataBusWidth, 12, 2)) re <- replicateM(mkMemReadEngine);
	Vector#(NumWriteClients, MemWriteEngine#(DataBusWidth, DataBusWidth,  1, 2)) we <- replicateM(mkMemWriteEngine); // TODO: more servers
	
	Reg#(Bit#(32)) dmaKtHighSgid <- mkReg(0);
	Reg#(Bit#(32)) dmaKtLowSgid <- mkReg(0);

	//Reg#(Bit#(32)) numHighKt <- mkReg(0);
	//Reg#(Bit#(32)) numLowKt <- mkReg(0);
	Reg#(Bit#(32)) reqSentHigh <- mkReg(0);
	Reg#(Bit#(32)) reqSentLow <- mkReg(0);

	// DMA write pointers: we[0] Result, we[1] Collected LPA
	Reg#(Bit#(32)) dmaKtResultSgid <- mkReg(0);
	Reg#(Bit#(32)) dmaAddrCollectSgid <- mkReg(0);

	FIFO#(Bit#(32)) hGenReqQ <- mkFIFO;
	rule h_generateReq;
		let reS = re[0].readServers[1];
		let dmaCmd = MemengineCmd {
			sglId: dmaKtHighSgid,
			base: reqSentHigh << keytableSizeLog,
			len: 8192,
			burstLen: fromInteger(dmaBurstBytes)
		};

		reS.request.put(dmaCmd);
		$display("[genHReq] %d, %d, %d, %d", dmaKtHighSgid, reqSentHigh<<keytableSizeLog, 8192, dmaBurstBytes);

		if (reqSentHigh == hGenReqQ.first-1) begin
			hGenReqQ.deq;
			reqSentHigh <= 0;
		end
		else begin
			reqSentHigh <= reqSentHigh+1;
		end
	endrule

	FIFO#(Bit#(32)) lGenReqQ <- mkFIFO;
	rule l_generateReq;
		let reS = re[0].readServers[0];
		let dmaCmd = MemengineCmd {
			sglId: dmaKtLowSgid,
			base: reqSentLow << keytableSizeLog,
			len: 8192,
			burstLen: fromInteger(dmaBurstBytes)
		};

		reS.request.put(dmaCmd);
		$display("[genLReq] %d, %d, %d, %d", dmaKtLowSgid, reqSentLow<<keytableSizeLog, 8192, dmaBurstBytes);

		if (reqSentLow == lGenReqQ.first-1) begin
			lGenReqQ.deq;
			reqSentLow <= 0;
		end
		else begin
			reqSentLow <= reqSentLow+1;
		end
	endrule

	FIFO#(Bit#(WordSz)) hKtBuffer <- mkSizedBRAMFIFO(1024);
	FIFO#(Bit#(WordSz)) lKtBuffer <- mkSizedBRAMFIFO(1024);

	Reg#(Bit#(32)) h_beatcnt <- mkReg(0);
	Reg#(Bit#(32)) l_beatcnt <- mkReg(0);
	rule h_pushkeytable;
		let d <- toGet(re[0].readServers[1].data).get;
		hKtBuffer.enq(d.data);
		$display("[hDMAbeat %d]", h_beatcnt);
		h_beatcnt<=h_beatcnt+1;
	endrule

	rule h_pushkeytable2;
		hKtBuffer.deq;
		merger.enqHighLevelKt(hKtBuffer.first);
	endrule

	rule l_pushkeytable;
		let d <- toGet(re[0].readServers[0].data).get;
		lKtBuffer.enq(d.data);
		$display("[lDMAbeat %d]", l_beatcnt);
		l_beatcnt<=l_beatcnt+1;
	endrule

	rule l_pushkeytable2;
		lKtBuffer.deq;
		merger.enqLowLevelKt(lKtBuffer.first);
	endrule

	Reg#(Bit#(32)) mergerOutputCnt <- mkReg(0);
	//FIFO#(Bit#(128)) dmaWriteOutPipe <- mkSizedFIFO;
	Vector#(4, FIFO#(Tuple2#(Bool,Bit#(128)))) dmaWriteOut <- replicateM(mkSizedBRAMFIFO(512));
	FIFO#(Bool) dmaWriteReqQ <- mkFIFO;
	Vector#(4, FIFO#(Bool)) dmaWriteReqToRespQ <- replicateM(mkSizedFIFO(8));
	//FIFO#(Bool) outGenReqQ <- mkFIFO;

	//rule outputKTFirst;
	//	outGenReqQ.deq;
	//	dmaWriteReqQ.enq(False);
	//endrule

	Reg#(Bit#(2)) phase1 <- mkReg(0);
	rule outputKT;
		let d <- merger.getMergedKt();
		let last = tpl_1(d);
		let data = tpl_2(d);
		dmaWriteOut[phase1].enq(d);

		mergerOutputCnt <= mergerOutputCnt + 1;
		Bit#(9) beatTruncate = truncate(mergerOutputCnt);

		$display("[outDMAbeat %d]", mergerOutputCnt);

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
	rule genDmaWReq;
		dmaWriteReqQ.deq;
		let weS = we[(phase2[0]==1?3:1)].writeServers[phase2[1]];
		let dmaCmd = MemengineCmd {
			sglId: dmaKtResultSgid,
			base: (ktResultReqSent<<keytableSizeLog),
			len: fromInteger(keytableBytes),
			burstLen: fromInteger(dmaBurstBytes)
		};
		weS.request.put(dmaCmd);
		$display("[genOutReq] %d, %d, %d, %d", dmaKtResultSgid, ktResultReqSent << keytableSizeLog, 8192, dmaBurstBytes);

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

	rule sendDmaWriteData0;
		dmaWriteOut[0].deq;
		let d = dmaWriteOut[0].first;
		let weS = we[1].writeServers[0];
		weS.data.enq(tpl_2(d));
	endrule 
	rule sendDmaWriteData1;
		dmaWriteOut[1].deq;
		let d = dmaWriteOut[1].first;
		let weS = we[3].writeServers[0];
		weS.data.enq(tpl_2(d));
	endrule 
	rule sendDmaWriteData2;
		dmaWriteOut[2].deq;
		let d = dmaWriteOut[2].first;
		let weS = we[1].writeServers[1];
		weS.data.enq(tpl_2(d));
	endrule 
	rule sendDmaWriteData3;
		dmaWriteOut[3].deq;
		let d = dmaWriteOut[3].first;
		let weS = we[3].writeServers[1];
		weS.data.enq(tpl_2(d));
	endrule 

	Reg#(Bit#(64)) counter <- mkReg(0);
	Reg#(Bit#(64)) counter_firstOut <- mkReg(0);
	(* fire_when_enabled *)
	rule cntUp;
		counter <= counter+1;
	endrule

	FIFO#(Bit#(32)) ktGeneratedDone0 <- mkFIFO;
	Reg#(Bit#(32)) ktGenerated0 <- mkReg(0);
	rule dmaWriteGetResponse0;
		dmaWriteReqToRespQ[0].deq;
		if (!dmaWriteReqToRespQ[0].first) begin
			let weS = we[1].writeServers[0];
			let dummy <- weS.done.get;
			ktGenerated0 <= ktGenerated0 + 1;

			if(ktGenerated0==0) counter_firstOut <= counter;
		end
		else begin
			ktGeneratedDone0.enq(ktGenerated0);
			ktGenerated0 <= 0;
		end
	endrule

	FIFO#(Bit#(32)) ktGeneratedDone1 <- mkFIFO;
	Reg#(Bit#(32)) ktGenerated1 <- mkReg(0);
	rule dmaWriteGetResponse1;
		dmaWriteReqToRespQ[1].deq;
		if (!dmaWriteReqToRespQ[1].first) begin
			let weS = we[3].writeServers[0];
			let dummy <- weS.done.get;
			ktGenerated1 <= ktGenerated1 + 1;
		end
		else begin
			ktGeneratedDone1.enq(ktGenerated1);
			ktGenerated1 <= 0;
		end
	endrule

	FIFO#(Bit#(32)) ktGeneratedDone2 <- mkFIFO;
	Reg#(Bit#(32)) ktGenerated2 <- mkReg(0);
	rule dmaWriteGetResponse2;
		dmaWriteReqToRespQ[2].deq;
		if (!dmaWriteReqToRespQ[2].first) begin
			let weS = we[1].writeServers[1];
			let dummy <- weS.done.get;
			ktGenerated2 <= ktGenerated2 + 1;
		end
		else begin
			ktGeneratedDone2.enq(ktGenerated2);
			ktGenerated2 <= 0;
		end
	endrule

	FIFO#(Bit#(32)) ktGeneratedDone3 <- mkFIFO;
	Reg#(Bit#(32)) ktGenerated3 <- mkReg(0);
	rule dmaWriteGetResponse3;
		dmaWriteReqToRespQ[3].deq;
		if (!dmaWriteReqToRespQ[3].first) begin
			let weS = we[3].writeServers[1];
			let dummy <- weS.done.get;
			ktGenerated3 <= ktGenerated3 + 1;
		end
		else begin
			ktGeneratedDone3.enq(ktGenerated3);
			ktGenerated3 <= 0;
		end
	endrule

	rule ind_mergeDone;
		ktGeneratedDone0.deq;
		ktGeneratedDone1.deq;
		ktGeneratedDone2.deq;
		ktGeneratedDone3.deq;
		let d0 = ktGeneratedDone0.first;
		let d1 = ktGeneratedDone1.first;
		let d2 = ktGeneratedDone2.first;
		let d3 = ktGeneratedDone3.first;
		indication.mergeDone(d0+d1+d2+d3, counter-counter_firstOut);
	endrule

	FIFO#(Bit#(1)) echoReqQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(32), Bit#(32))) mergeReqQ <- mkFIFO;

	rule echoBack;
		echoReqQ.deq;
		indication.echoBack(11);
	endrule

	rule pushRequest;
		mergeReqQ.deq;
		let d = mergeReqQ.first;
		hGenReqQ.enq(tpl_1(d));
		lGenReqQ.enq(tpl_2(d));
		//outGenReqQ.enq(?);
		merger.runMerge(tpl_1(d), tpl_2(d));
		$display("[runMerge] %d %d", tpl_1(d), tpl_2(d));
	endrule

	Vector#(NumWriteClients, MemWriteClient#(DataBusWidth)) dmaWriteClientVec;
	Vector#(NumReadClients, MemReadClient#(DataBusWidth)) dmaReadClientVec;

	for (Integer tt = 0; tt < valueOf(NumReadClients); tt=tt+1) begin
		dmaReadClientVec[tt] = re[tt].dmaClient;
	end

	for (Integer tt = 0; tt < valueOf(NumWriteClients); tt=tt+1) begin
		dmaWriteClientVec[tt] = we[tt].dmaClient;
	end

	interface dmaWriteClient = dmaWriteClientVec;
	interface dmaReadClient = dmaReadClientVec;

	interface KtRequest request;
		method Action runMerge(Bit#(32) numHigh, Bit#(32) numLow);
			mergeReqQ.enq(tuple2(numHigh, numLow));
		endmethod

		method Action echoSecret(Bit#(32) dummy);
			echoReqQ.enq(?);
		endmethod

		method Action setKtHighRef(Bit#(32) sgId);
			dmaKtHighSgid <= sgId;
		endmethod
		method Action setKtLowRef(Bit#(32) sgId);
			dmaKtLowSgid <= sgId;
		endmethod
		method Action setResultRef(Bit#(32) sgId);
			dmaKtResultSgid <= sgId;
		endmethod
		method Action setCollectedAddrRef(Bit#(32) sgId);
			dmaAddrCollectSgid <= sgId;
		endmethod
	endinterface
endmodule
