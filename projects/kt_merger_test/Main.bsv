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
	method Action mergeDone(Bit#(32) numGenKt);
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

	Vector#(NumReadClients, MemReadEngine#(DataBusWidth, DataBusWidth, 1, 1)) re <- replicateM(mkMemReadEngine);
	Vector#(NumWriteClients, MemWriteEngine#(DataBusWidth, DataBusWidth,  1, 1)) we <- replicateM(mkMemWriteEngine);
	
	// DMA read pointers: re[0] High, re[1] Low
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
		let reS = re[0].readServers[0];
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
		let reS = re[1].readServers[0];
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

//	FIFO#(Bit#(32)) lGenReqQ <- mkFIFO;
//	rule l_generateReq;
//		let reS = re[1].readServers[0];
//		let dmaCmd = MemengineCmd {
//			sglId: dmaKtLowSgid,
//			base: 0,
//			len: lGenReqQ.first << keytableSizeLog,
//			burstLen: fromInteger(dmaBurstBytes)
//		};
//		reS.request.put(dmaCmd);
//		$display("l_genReq: %d, %d, %d, %d", dmaKtLowSgid, 0, lGenReqQ.first << keytableSizeLog, dmaBurstBytes);
//
//		lGenReqQ.deq;
//	endrule

	FIFO#(Bit#(WordSz)) hKtBuffer <- mkSizedBRAMFIFO(1024);
	FIFO#(Bit#(WordSz)) lKtBuffer <- mkSizedBRAMFIFO(1024);

	Reg#(Bit#(32)) h_beatcnt <- mkReg(0);
	Reg#(Bit#(32)) l_beatcnt <- mkReg(0);
	rule h_pushkeytable;
		let d <- toGet(re[0].readServers[0].data).get;
		hKtBuffer.enq(d.data);
		$display("[hDMAbeat %d]", h_beatcnt);
		h_beatcnt<=h_beatcnt+1;
	endrule

	rule h_pushkeytable2;
		hKtBuffer.deq;
		merger.enqHighLevelKt(hKtBuffer.first);
	endrule

	rule l_pushkeytable;
		let d <- toGet(re[1].readServers[0].data).get;
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
	FIFO#(Bit#(128)) dmaWriteOut <- mkSizedFIFO(16);
	FIFO#(Bool) dmaWriteReqQ <- mkFIFO;
	FIFO#(Bool) dmaWriteReqToRespQ <- mkFIFO;

	rule outputKT;
		let d <- merger.getMergedKt();
		let last = tpl_1(d);
		let data = tpl_2(d);
		dmaWriteOut.enq(data);

		mergerOutputCnt <= mergerOutputCnt + 1;
		Bit#(9) beatTruncate = truncate(mergerOutputCnt);

		$display("[outDMAbeat %d]", mergerOutputCnt);

		if (beatTruncate == 0) begin
			dmaWriteReqQ.enq(last);
		end
	endrule

	Reg#(Bit#(32)) ktResultReqSent <- mkReg(0);
	rule genDmaWReq;
		dmaWriteReqQ.deq;

		let weS = we[0].writeServers[0];
		let dmaCmd = MemengineCmd {
			sglId: dmaKtResultSgid,
			base: (ktResultReqSent<<keytableSizeLog),
			len: fromInteger(keytableBytes),
			burstLen: fromInteger(dmaBurstBytes)
		};
		weS.request.put(dmaCmd);
		$display("[genOutReq] %d, %d, %d, %d", dmaKtResultSgid, ktResultReqSent << keytableSizeLog, 8192, dmaBurstBytes);

		dmaWriteReqToRespQ.enq(dmaWriteReqQ.first);
		if(dmaWriteReqQ.first) begin
			ktResultReqSent <= 0;
		end
		else begin
			ktResultReqSent <= ktResultReqSent + 1;
		end
	endrule

	rule sendDmaWriteData;
		let d = dmaWriteOut.first;
		dmaWriteOut.deq;

		let weS = we[0].writeServers[0];
		weS.data.enq(d);
	endrule

	Reg#(Bit#(32)) ktGenerated <- mkReg(0);
	rule dmaWriteGetResponse;
		let weS = we[0].writeServers[0];
		let dummy <- weS.done.get;

		let last = dmaWriteReqToRespQ.first;
		dmaWriteReqToRespQ.deq;
		
		if (last) begin
			ktGenerated <= 0;
			indication.mergeDone(ktGenerated+1);
		end
		else begin
			ktGenerated <= ktGenerated + 1;
		end
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
