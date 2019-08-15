import RWBramCore::*;
import RegFile::*;
import FIFO::*;
import GetPut::*;
import Vector::*;
import SpecialFIFOs::*;

interface RenameTable#(numeric type numTags, type dataT);
	method ActionValue#(Bit#(TLog#(numTags))) writeEntry(dataT d);
	method Action readEntry0(Bit#(TLog#(numTags)) tag);
	method Action readEntry1(Bit#(TLog#(numTags)) tag);
	method Action readEntry2(Bit#(TLog#(numTags)) tag);
	method ActionValue#(dataT) readResp0;
	method ActionValue#(dataT) readResp1;
	method ActionValue#(dataT) readResp2;
	method Action invalidEntry(Bit#(TLog#(numTags)) tag);
endinterface

module mkRenameTable(RenameTable#(numTags, dataT)) provisos(
	NumAlias#(TExp#(TLog#(numTags)), numTags),
	Bits#(dataT, a__)
	);
	Reg#(Bit#(TLog#(numTags))) initCnt <- mkReg(0);
	Reg#(Bool) init <- mkReg(False);

	FIFO#(Bit#(TLog#(numTags))) freeTagQ <- mkSizedFIFO(valueOf(numTags));

	`ifdef USE_BRAM
	RWBramCore#(Bit#(TLog#(numTags)), dataT) tb <- mkRWBramCore;
	`else
	Vector#(3, FIFO#(Bit#(TLog#(numTags)))) readReqQ <- replicateM(mkFIFO);
	RegFile#(Bit#(TLog#(numTags)), dataT) tb <- mkRegFileFull;
	`endif

	rule initialize (!init);
		$display("initCnt = %d", initCnt);
		initCnt <= initCnt + 1;
		freeTagQ.enq(initCnt);
		if (initCnt == fromInteger(valueOf(numTags) - 1))
			init <= True;
	endrule

	method ActionValue#(Bit#(TLog#(numTags))) writeEntry(dataT d) if (init);
		let freeTag = freeTagQ.first;
		freeTagQ.deq;
		`ifdef USE_BRAM
		tb.wrReq(freeTag, d);
		`else
		tb.upd(freeTag, d);
		`endif
		return freeTag;
	endmethod

	method Action readEntry0(Bit#(TLog#(numTags)) tag);
		`ifdef USE_BRAM
		tb.rdReq(tag);
		`else
		readReqQ[0].enq(tag);
		`endif
	endmethod
	method Action readEntry1(Bit#(TLog#(numTags)) tag);
		`ifdef USE_BRAM
		tb.rdReq(tag);
		`else
		readReqQ[1].enq(tag);
		`endif
	endmethod
	method Action readEntry2(Bit#(TLog#(numTags)) tag);
		`ifdef USE_BRAM
		tb.rdReq(tag);
		`else
		readReqQ[2].enq(tag);
		`endif
	endmethod

	method ActionValue#(dataT) readResp0;
		`ifdef USE_BRAM
		tb.deqRdResp;
		return tb.rdResp;
		`else
		let tag <- toGet(readReqQ[0]).get;
		return tb.sub(tag);
		`endif
	endmethod
	method ActionValue#(dataT) readResp1;
		`ifdef USE_BRAM
		tb.deqRdResp;
		return tb.rdResp;
		`else
		let tag <- toGet(readReqQ[1]).get;
		return tb.sub(tag);
		`endif
	endmethod
	method ActionValue#(dataT) readResp2;
		`ifdef USE_BRAM
		tb.deqRdResp;
		return tb.rdResp;
		`else
		let tag <- toGet(readReqQ[2]).get;
		return tb.sub(tag);
		`endif
	endmethod

	method Action invalidEntry(Bit#(TLog#(numTags)) tag) if (init); 
		freeTagQ.enq(tag);
	endmethod	
endmodule

