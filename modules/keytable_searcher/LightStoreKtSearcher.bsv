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

import FlashCtrlIfc::*;
import ControllerTypes::*;

// WordBytes defined as "16"  in ControllerTypes.bsv
// WordSz    defined as "128" in ControllerTypes.bsv

typedef 8192 KeytableBytes;

// First 1-KB of Keytable is KtHeader
// KtHeader is an array of 2B (512 Elements)
// KtHeader[0] = # of Entry = N
// KtHeader[k] = Byte-Offset of k-th Keytable Entry. Note that KtHeader[1] is always 1024 (Starts at 1-KB)
// KtHeader[N+1] = Byte-Offset of the Byte that follows the last entry
typedef 1024 KtHeaderBytes;
typedef 2 HeaderElemBytes;
typedef TMul#(8, HeaderElemBytes) HeaderElemSz;
typedef TDiv#(WordBytes, HeaderElemBytes) WordHeaderElems; // 8 header entries per word

Integer wordHeaderElems = valueOf(WordHeaderElems); // 1 word = 8 header elems

typedef TDiv#(KeytableBytes, WordBytes) KeytableWords; // = 512
typedef TDiv#(KtHeaderBytes, WordBytes) KtHeaderWords; // = 64
typedef TDiv#(KtHeaderBytes, HeaderElemBytes) KtHeaderElems; // = 512

Integer keytableBytes = valueOf(KeytableBytes); // = 8192
Integer keytableWords = valueOf(KeytableWords); // = 512
Integer ktHeaderWords = valueOf(KtHeaderWords); // = 64
Integer ktHeaderElems = valueOf(KtHeaderElems); // = 512

typedef enum { GT, LT, EQ } CompResult deriving (Bits, Eq);

function CompResult compareByteString1(Bit#(96) a, Bit#(96) b);
	Vector#(12, Bit#(8)) a_vec = unpack(a);
	Vector#(12, Bit#(8)) b_vec = unpack(b);

	Bit#(96) a_new = pack(reverse(a_vec));
	Bit#(96) b_new = pack(reverse(b_vec));

	if (a_new>b_new) return GT;
	else if(a_new==b_new) return EQ;
	else return LT;
endfunction

function CompResult compareByteString(Bit#(128) a, Bit#(128) b);
	Vector#(16, Bit#(8)) a_vec = unpack(a);
	Vector#(16, Bit#(8)) b_vec = unpack(b);

	Bit#(128) a_new = pack(reverse(a_vec));
	Bit#(128) b_new = pack(reverse(b_vec));

	if (a_new>b_new) return GT;
	else if(a_new==b_new) return EQ;
	else return LT;
endfunction

typedef enum {
	LOAD_KEY,
	FIND_KEY1,
	FIND_KEY2,
	FLUSH_ONE_ENTRY,
	FLUSH_TABLE
} SearchStatus deriving (Bits, Eq);

// 1~16 Beat keys (16B - 256B); 16 encoded as "0" -> Total 4 Bits
typedef 16 MaxKeyBeat;
typedef Bit#(TLog#(MaxKeyBeat)) KeyBeatT; 

interface LightStoreKtSearcher;
	method Action findKey(Bit#(32) ppa, KeyBeatT keySz, TagT tag);
	method ActionValue#(Tuple2#(Maybe#(Bit#(32)), TagT)) findKeyDone;
	method Action setSearchKeyRef(Bit#(32) sgId);
endinterface

module mkLightStoreKtSearcher #(
	MemReadEngineServer#(DataBusWidth) rs,
	Server#(DualFlashAddr, Bit#(128)) flashRs
) (LightStoreKtSearcher);
	Reg#(Bit#(32)) keySgid <- mkReg(0);
	FIFO#(Tuple3#(Bit#(32), KeyBeatT, TagT)) reqQ <- mkFIFO;
	FIFO#(Tuple2#(Maybe#(Bit#(32)), TagT)) respQ <- mkFIFO;


	FIFO#(Tuple2#(KeyBeatT, TagT)) dmaReqQ <- mkSizedBRAMFIFO(64);
	FIFO#(Tuple2#(KeyBeatT, TagT)) reqToRespQ <- mkSizedFIFO(8);

	rule initReq;
		let {ppa, keySz, tag} <- toGet(reqQ).get;
		flashRs.request.put(toDualFlashAddr(ppa));
		dmaReqQ.enq(tuple2(keySz, tag));
	endrule

	// Flash Read
	Vector#(WordHeaderElems, FIFOF#(Bit#(HeaderElemSz))) hdrParserBuf <- replicateM(mkSizedBRAMFIFOF(ktHeaderWords)); // 1KB
	FIFOF#(Bool) hdrParserIsLast <- mkFIFOF();

	Reg#(Bit#(HeaderElemSz)) numEnt <- mkReg(0);
	Reg#(Bit#(HeaderElemSz)) lastEntOffset <- mkReg(0);
	Reg#(Bit#(16)) keytableInBeat <- mkReg(0);

	FIFOF#(Bit#(WordSz)) ktEntryStream <- mkFIFOF;
	FIFOF#(Maybe#(Bit#(5))) ktBeatSzStream <- mkFIFOF;

	rule splitHeader;
		let w <- flashRs.response.get();

		// keytableInBeat update
		if (keytableInBeat == fromInteger(pageWords-1)) // (514 Beats = 8192+32)
			keytableInBeat <= 0;
		else keytableInBeat <= keytableInBeat+1;

		// split header
		if (keytableInBeat < fromInteger(ktHeaderWords)) begin // Header
			Vector#(WordHeaderElems, Bit#(HeaderElemSz)) headerEntries = unpack(w);
			for (Integer j = 0; j < valueOf(WordHeaderElems); j=j+1) begin
				hdrParserBuf[j].enq(headerEntries[j]);
			end

			if(keytableInBeat == 0) begin // if first beat,
				numEnt <= headerEntries[0];

				let idxOffset = headerEntries[0]+1;
				if(idxOffset < 8) begin
					lastEntOffset <= headerEntries[idxOffset[2:0]];
				end
			end
			else if (keytableInBeat==((numEnt+1)>>3)) begin
				let idxOffset = numEnt + 1;
				lastEntOffset <= headerEntries[idxOffset[2:0]];
			end
		end
		else if (keytableInBeat < fromInteger(keytableWords)) begin // Keytable body
			if (keytableInBeat < (lastEntOffset >> 4)) // push only valid entries
				ktEntryStream.enq(w);
		end // extra 32B dropped
	endrule

	Reg#(Bit#(16)) scannedHdrElems <- mkReg(0);
	Reg#(Bit#(16)) numKtEntries <- mkReg(0);
	Reg#(Bit#(HeaderElemSz)) prevOffset <- mkReg(0);

	rule parseHeader;
		if (scannedHdrElems == 0) begin
			let entries = hdrParserBuf[0].first;
			numKtEntries <= (entries>510)?510:entries; // Max # entry = 510

			prevOffset <= 1024; // hdrParserBuf[1].first is always 1024

			hdrParserBuf[0].deq;
			hdrParserBuf[1].deq;

			scannedHdrElems <= 2; // 2 header elements processed
		end
		else if (scannedHdrElems < numKtEntries + 2) begin // k keytable entries => (k+2)-header elements
			let nextOffset <- toGet(hdrParserBuf[scannedHdrElems[2:0]]).get;
			prevOffset <= nextOffset;

			Bit#(5) entryBeats = truncate( (nextOffset-prevOffset) >> 4 );
			if (entryBeats>16) entryBeats = 16; // Max beats = 16
			if (entryBeats==0) entryBeats = 1;  // Min beats = 1

			ktBeatSzStream.enq( tagged Valid entryBeats );  // offset difference / 16 -> Beat

			if (scannedHdrElems == fromInteger(ktHeaderElems)-1) scannedHdrElems <= 0;
			else scannedHdrElems <= scannedHdrElems+1;
		end
		else if (scannedHdrElems < fromInteger(ktHeaderElems)) begin
			if (scannedHdrElems == numKtEntries+2) begin
				// keytable header scan done -> signal last element
				ktBeatSzStream.enq( tagged Invalid );
			end

			if ( fromInteger(ktHeaderElems)-scannedHdrElems >= fromInteger(wordHeaderElems) ) begin
				for (Integer j = 0; j < valueOf(WordHeaderElems); j=j+1) begin
					hdrParserBuf[j].deq;
				end

				if (scannedHdrElems == fromInteger(ktHeaderElems-wordHeaderElems)) scannedHdrElems <= 0;
				else scannedHdrElems <= scannedHdrElems+fromInteger(wordHeaderElems);
			end
			else begin
				hdrParserBuf[scannedHdrElems[2:0]].deq;

				if (scannedHdrElems == fromInteger(ktHeaderElems)-1) scannedHdrElems <= 0;
				else scannedHdrElems <= scannedHdrElems+1;
			end
		end
	endrule

	// DMA Req & DMA Read (Keys)
	rule driveDma;
		let {keySz, tag} <- toGet(dmaReqQ).get;

		Bit#(9) dmaLength = (keySz==0)?256:(zeroExtend(keySz)<<4);
		let dmaCmd = MemengineCmd {
							sglId: keySgid, 
							base: zeroExtend(tag)<<8, // <<8 or *256
							len: zeroExtend(dmaLength), 
							burstLen: zeroExtend(dmaLength)
						};
		rs.request.put(dmaCmd);

		reqToRespQ.enq(dmaReqQ.first);
	endrule

	// Key Search
	let {keyToSearchSz, reqTag} = reqToRespQ.first;

	Reg#(SearchStatus) st <- mkReg(LOAD_KEY);
	Reg#(KeyBeatT) keyLoadBeat <- mkReg(0);
	Reg#(KeyBeatT) compareBeat <- mkReg(0);
	Vector#(MaxKeyBeat, Reg#(Bit#(128))) keyToSearch <- replicateM(mkRegU);

	rule loadKey (st == LOAD_KEY);
		let d <- toGet(rs.data).get;
		keyToSearch[keyLoadBeat] <= d.data;

		if ( keyLoadBeat == (keyToSearchSz-1) ) begin
			keyLoadBeat <= 0;
			compareBeat <= 0;
			st <= FIND_KEY1;
		end
		else keyLoadBeat <= keyLoadBeat+1;
	endrule

	Reg#(Bit#(32)) curEntryPpa <- mkReg(0);
	KeyBeatT entryBeatSz = truncate(fromMaybe(?, ktBeatSzStream.first));

	rule compareKey (st == FIND_KEY1); // compareBeat is 0 in this rule
		if (!isValid(ktBeatSzStream.first)) begin // Current KT done
			ktBeatSzStream.deq;
			reqToRespQ.deq;
			respQ.enq(tuple2(tagged Invalid, reqTag)); // did not find
			st <= LOAD_KEY;
		end
		else if (keyToSearchSz != entryBeatSz) begin
			ktEntryStream.deq;
			if (entryBeatSz == 1) begin
				ktBeatSzStream.deq;
			end
			else begin
				compareBeat <= 1;
				st <= FLUSH_ONE_ENTRY;
			end
		end
		else begin
			let ppa = ktEntryStream.first[31:0];
			curEntryPpa <= ppa;

			CompResult res = compareByteString1(keyToSearch[0][127:32], ktEntryStream.first[127:32]);

			if (res == LT) begin
				reqToRespQ.deq;
				respQ.enq(tuple2(tagged Invalid, reqTag));
				st <= FLUSH_TABLE;
			end
			else if (res == GT) begin
				ktEntryStream.deq;
				if (entryBeatSz == 1) begin
					ktBeatSzStream.deq;
				end
				else begin
					compareBeat <= 1;
					st <= FLUSH_ONE_ENTRY;
				end
			end
			else begin
				ktEntryStream.deq;
				if (entryBeatSz == 1) begin
					ktBeatSzStream.deq;
					reqToRespQ.deq;
					respQ.enq(tuple2(tagged Valid ppa, reqTag));
					st <= FLUSH_TABLE;
				end
				else begin
					compareBeat <= 1;
					st <= FIND_KEY2;
				end
			end
		end
	endrule

	rule compareKey2 (st == FIND_KEY2);
		let ppa = curEntryPpa;
		CompResult res = compareByteString(keyToSearch[compareBeat], ktEntryStream.first);

		if (res == LT) begin
			reqToRespQ.deq;
			respQ.enq(tuple2(tagged Invalid, reqTag));
			st <= FLUSH_TABLE;
		end
		else if (res == GT) begin
			ktEntryStream.deq;
			if (compareBeat == entryBeatSz-1) begin
				ktBeatSzStream.deq;
				compareBeat <= 0;
				st <= FIND_KEY1;
			end
			else begin
				compareBeat <= compareBeat + 1;
				st <= FLUSH_ONE_ENTRY;
			end
		end
		else begin
			ktEntryStream.deq;
			if (compareBeat == entryBeatSz-1) begin
				ktBeatSzStream.deq;
				reqToRespQ.deq;
				respQ.enq(tuple2(tagged Valid ppa, reqTag));
				st <= FLUSH_TABLE;
				compareBeat <= 0;
			end
			else begin
				compareBeat <= compareBeat + 1;
			end
		end
	endrule

	rule flushPage (st == FLUSH_TABLE);
		if (isValid(ktBeatSzStream.first)) begin
			ktEntryStream.deq;
			if (compareBeat == entryBeatSz-1) begin
				compareBeat <= 0;
				ktBeatSzStream.deq;
			end
			else compareBeat <= compareBeat+1;
		end
		else begin
			ktBeatSzStream.deq;
			st <= LOAD_KEY;
		end
	endrule

	rule flushOneEntry (st == FLUSH_ONE_ENTRY);
		ktEntryStream.deq;
		if (compareBeat == entryBeatSz-1) begin
			st <= FIND_KEY1;
			compareBeat <= 0;
			ktBeatSzStream.deq;
		end
		else compareBeat <= compareBeat+1;
	endrule

	//////////////////
	// Interface
	//////////////////
	method Action findKey(Bit#(32) ppa, KeyBeatT keySz, TagT tag);
		reqQ.enq(tuple3(ppa, keySz, tag)); // keySz=0 means 16
	endmethod

	method ActionValue#(Tuple2#(Maybe#(Bit#(32)), TagT)) findKeyDone = toGet(respQ).get;

	method Action setSearchKeyRef(Bit#(32) sgId);
		keySgid <= sgId;
	endmethod
endmodule
