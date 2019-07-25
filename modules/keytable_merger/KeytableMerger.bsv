import DefaultValue::*;
import BRAM::*;
import BRAMFIFO::*;

import FIFO::*;
import FIFOF::*;

import Vector::*;
import BuildVector::*;

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

typedef enum { DECISION, HIGH_FLUSH, LOW_FLUSH } MStatus deriving (Bits, Eq);

typedef enum {
	READY,    // need to set the number of both Kts
	OPERATING
} MergerStatus deriving (Bits, Eq);

interface MergeKeytable;
	method Action runMerge(Bit#(32) numHighLvlKt, Bit#(32) numLowLvlKt);

	method Action enqHighLevelKt(Bit#(WordSz) beat);
	method Action enqLowLevelKt(Bit#(WordSz) beat);

	// method MergerStatus mergerStatus();
	method ActionValue#(Tuple2#(Bool,Bit#(WordSz))) getMergedKt();
	method ActionValue#(Bit#(32)) getCollectedAddr();
endinterface

(* synthesize *)
module mkMergeKeytable (MergeKeytable ifc);

	Reg#(Bit#(32)) cnt <- mkReg(0);

	rule cntUP;
		cnt <= cnt+1;
	endrule

	// [0]: High Level (N)
	// [1]: Low Level (N+1)
	Vector#(2, Reg#(Bit#(32))) numKeytable <- replicateM(mkReg(0));
	Vector#(2, Reg#(Bit#(32))) numKeytableOrig <- replicateM(mkReg(0));
	Vector#(2, Reg#(Bit#(16))) keytableInBeat <- replicateM(mkReg(0));
	Vector#(2, FIFOF#(Bit#(WordSz))) keytableIn <- replicateM(mkFIFOF);

	// Vector#(2, FIFOF#(Bit#(WordSz))) ktEntryIn <- replicateM(mkFIFOF);
	Vector#(2, FIFOF#(Bit#(WordSz))) ktEntryStream <- replicateM(mkFIFOF);
	Vector#(2, FIFOF#(Maybe#(Bit#(5)))) ktBeatCntStream <- replicateM(mkFIFOF);

	FIFOF#(Bit#(WordSz)) newEntryBuf <- mkSizedBRAMFIFOF(keytableWords); // KeytableWords-ktHeaderWords
	FIFOF#(Maybe#(Bit#(5))) mergedSizeInfo <- mkFIFOF;

	FIFOF#(Tuple2#(Bool, Bit#(WordSz))) createdKtStream <- mkFIFOF;

	FIFOF#(Bit#(32)) collectedAddrQ <- mkFIFOF;

	// Pre-processing header
	for(Integer i=0; i<2; i=i+1) begin
		Vector#(WordHeaderElems, FIFOF#(Bit#(HeaderElemSz))) hdrParserBuf <- replicateM(mkSizedBRAMFIFOF(ktHeaderWords)); // 1KB
		FIFOF#(Bool) hdrParserIsLast <- mkFIFOF();

		Reg#(Bit#(HeaderElemSz)) numEnt <- mkReg(0);
		Reg#(Bit#(HeaderElemSz)) lastEntOffset <- mkReg(0);

		rule splitHeader ( numKeytable[i] > 0 );
			let w = keytableIn[i].first;
			keytableIn[i].deq;

			if (keytableInBeat[i] < fromInteger(ktHeaderWords)) begin // Header
				Vector#(WordHeaderElems, Bit#(HeaderElemSz)) headerEntries = unpack(w);
				for (Integer j = 0; j < valueOf(WordHeaderElems); j=j+1) begin
					hdrParserBuf[j].enq(headerEntries[j]);
				end

				keytableInBeat[i] <= keytableInBeat[i] + 1;

				if(keytableInBeat[i] == 0) begin
					//$display("[%d] Port%d, KT %d-th start ", cnt, i, numKeytableOrig[i]-numKeytable[i]+1);
					//first beat
					hdrParserIsLast.enq(numKeytable[i]==1?True:False);
					numEnt <= headerEntries[0];

					let idxOffset = headerEntries[0]+1;
					if(idxOffset < 8) begin
						lastEntOffset <= headerEntries[idxOffset[2:0]];
					end
				end
				else if (keytableInBeat[i]==((numEnt+1)>>3)) begin
					let idxOffset = numEnt + 1;
					lastEntOffset <= headerEntries[idxOffset[2:0]];
				end
			end
			else if (keytableInBeat[i] < fromInteger(keytableWords)) begin // Keytable body
				if (keytableInBeat[i] < (lastEntOffset >> 4))
					ktEntryStream[i].enq(w);

				if (keytableInBeat[i] < fromInteger(keytableWords)-1) begin
					keytableInBeat[i] <= keytableInBeat[i] + 1;
				end
				else begin
					keytableInBeat[i] <= 0;
					numKeytable[i] <= numKeytable[i] - 1;
					//$display("[%d] Port%d, KT %d-th ended ", cnt, i, numKeytableOrig[i]-numKeytable[i]+1);
				end
			end
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

				ktBeatCntStream[i].enq( tagged Valid entryBeats );  // offset difference / 16 -> Beat

				if (scannedHdrElems == fromInteger(ktHeaderElems)-1) scannedHdrElems <= 0;
				else scannedHdrElems <= scannedHdrElems+1;
			end
			else if (scannedHdrElems < fromInteger(ktHeaderElems)) begin
				if (scannedHdrElems == numKtEntries+2) begin
					hdrParserIsLast.deq;
					if (hdrParserIsLast.first) begin
						// last keytable -> signal flush
						ktBeatCntStream[i].enq( tagged Invalid );
					end
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
	end

	Reg#(MStatus) curMStatus <- mkReg(DECISION);
	// [0]: High Level (N)
	FIFOF#(Bit#(WordSz)) h_ktEntryStream = ktEntryStream[0]; // rename
	FIFOF#(Maybe#(Bit#(5))) h_ktBeatCntStream = ktBeatCntStream[0]; // rename

	Vector#(16, Reg#(Maybe#(Bit#(WordSz)))) h_entryBuf <- replicateM(mkReg(tagged Invalid)); // each entry == max 16 beat = 256B
	//Reg#(Bit#(5)) h_numBufValid <- mkReg(0);

	Reg#(Bit#(4))  h_entryBeatSent <- mkReg(0);
	//Reg#(Bit#(10)) h_accmBeat <- mkReg(0);

	// [1]: Low Level (N+1)
	FIFOF#(Bit#(WordSz)) l_ktEntryStream = ktEntryStream[1]; // rename
	FIFOF#(Maybe#(Bit#(5))) l_ktBeatCntStream = ktBeatCntStream[1]; // rename

	Vector#(16, Reg#(Maybe#(Bit#(WordSz)))) l_entryBuf <- replicateM(mkReg(tagged Invalid)); // each entry == max 16 beat = 256B
	//Reg#(Bit#(5)) l_numBufValid <- mkReg(0);

	Reg#(Bit#(4))  l_entryBeatSent <- mkReg(0);
	//Reg#(Bit#(10)) l_accmBeat <- mkReg(0);

	Reg#(Bit#(4)) decPhaseCnt <- mkReg(0);
	let h_signalDone = !isValid(h_ktBeatCntStream.first);
	let l_signalDone = !isValid(l_ktBeatCntStream.first);

	rule flushTable (curMStatus == DECISION && (h_signalDone || l_signalDone) );
		if (h_signalDone && l_signalDone) begin
			// KT Merge: entry process completion
			h_ktBeatCntStream.deq;
			l_ktBeatCntStream.deq;

			// TODO: signal downstream to flush KT
			mergedSizeInfo.enq(tagged Invalid);
		end
		else if (h_signalDone && !l_signalDone ) begin
			if(isValid(l_entryBuf[0])) begin
				newEntryBuf.enq(fromMaybe(?, l_entryBuf[0]));
				l_entryBuf[0] <= tagged Invalid;
			end
			else begin
				newEntryBuf.enq(l_ktEntryStream.first);
				l_ktEntryStream.deq;
			end

			let curEntSzInBeats = fromMaybe(?, l_ktBeatCntStream.first);
			if (curEntSzInBeats == 1) begin
				l_ktBeatCntStream.deq;
				mergedSizeInfo.enq(tagged Valid curEntSzInBeats);
			end
			else begin
				curMStatus <= LOW_FLUSH;
				l_entryBeatSent <= 1;
			end
		end
		else if (!h_signalDone && l_signalDone ) begin
			if(isValid(h_entryBuf[0])) begin
				newEntryBuf.enq(fromMaybe(?, h_entryBuf[0]));
				h_entryBuf[0] <= tagged Invalid;
			end
			else begin
				newEntryBuf.enq(h_ktEntryStream.first);
				h_ktEntryStream.deq;
			end

			let curEntSzInBeats = fromMaybe(?, h_ktBeatCntStream.first);
			if (curEntSzInBeats == 1) begin
				h_ktBeatCntStream.deq;
				mergedSizeInfo.enq(tagged Valid curEntSzInBeats);
			end
			else begin
				curMStatus <= HIGH_FLUSH;
				h_entryBeatSent <= 1;
			end
		end
	endrule

	rule decision1 (curMStatus == DECISION && !h_signalDone && !l_signalDone);
		// words to compare
		Bit#(WordSz) h_word, l_word;
		if(isValid(h_entryBuf[decPhaseCnt])) begin
			h_word = fromMaybe(?, h_entryBuf[decPhaseCnt]);
		end
		else begin
			h_word = h_ktEntryStream.first;
		end

		if(isValid(l_entryBuf[decPhaseCnt])) begin
			l_word = fromMaybe(?, l_entryBuf[decPhaseCnt]);
		end
		else begin
			l_word = l_ktEntryStream.first;
		end

		CompResult res = (decPhaseCnt == 0)?
						compareByteString1(h_word[127:32], l_word[127:32]):
						compareByteString(h_word, l_word);

		if (res == GT) begin // FLUSH Low level entry
			if(isValid(l_entryBuf[0])) begin
				newEntryBuf.enq(fromMaybe(?, l_entryBuf[0]));
				l_entryBuf[0] <= tagged Invalid;
			end
			else begin
				newEntryBuf.enq(l_ktEntryStream.first);
				l_ktEntryStream.deq;
			end

			let curEntSzInBeats = fromMaybe(?, l_ktBeatCntStream.first);
			if (curEntSzInBeats == 1) begin
				l_ktBeatCntStream.deq;
				mergedSizeInfo.enq(tagged Valid curEntSzInBeats);
			end
			else begin
				curMStatus <= LOW_FLUSH;
				l_entryBeatSent <= 1;
			end
		end
		else if (res == LT) begin // FLUSH High level entry
			if(isValid(h_entryBuf[0])) begin
				newEntryBuf.enq(fromMaybe(?, h_entryBuf[0]));
				h_entryBuf[0] <= tagged Invalid;
			end
			else begin
				newEntryBuf.enq(h_ktEntryStream.first);
				h_ktEntryStream.deq;
			end

			let curEntSzInBeats = fromMaybe(?, h_ktBeatCntStream.first);
			if (curEntSzInBeats == 1) begin
				h_ktBeatCntStream.deq;
				mergedSizeInfo.enq(tagged Valid curEntSzInBeats);
			end
			else begin
				curMStatus <= HIGH_FLUSH;
				h_entryBeatSent <= 1;
			end
		end
		else if (res == EQ) begin // EQ
			let h_curEntSzInBeats = fromMaybe(?, h_ktBeatCntStream.first);
			let l_curEntSzInBeats = fromMaybe(?, l_ktBeatCntStream.first);

			Bool h_moreBeat = ( h_curEntSzInBeats - zeroExtend(decPhaseCnt) ) > 1 ;
			Bool l_moreBeat = ( l_curEntSzInBeats - zeroExtend(decPhaseCnt) ) > 1 ;

			if ( h_moreBeat && l_moreBeat ) begin // check next word
				decPhaseCnt <= decPhaseCnt + 1;

				if(!isValid(h_entryBuf[decPhaseCnt])) begin
					h_ktEntryStream.deq;
					h_entryBuf[decPhaseCnt] <= tagged Valid h_ktEntryStream.first;
				end

				if(!isValid(l_entryBuf[decPhaseCnt])) begin
					l_ktEntryStream.deq;
					l_entryBuf[decPhaseCnt] <= tagged Valid l_ktEntryStream.first;
				end
			end
			else if ( h_moreBeat && !l_moreBeat) begin // low level is smaller
				decPhaseCnt <= 0;

				if(isValid(l_entryBuf[0])) begin
					newEntryBuf.enq(fromMaybe(?, l_entryBuf[0]));
					l_entryBuf[0] <= tagged Invalid;
				end
				else begin
					newEntryBuf.enq(l_ktEntryStream.first);
					l_ktEntryStream.deq;
				end

				if (l_curEntSzInBeats == 1) begin
					l_ktBeatCntStream.deq;
					mergedSizeInfo.enq(tagged Valid l_curEntSzInBeats);
				end
				else begin
					curMStatus <= LOW_FLUSH;
					l_entryBeatSent <= 1;
				end
			end
			else if (!h_moreBeat) begin // high level is smaller or Equal
				decPhaseCnt <= 0;

				if(isValid(h_entryBuf[0])) begin
					newEntryBuf.enq(fromMaybe(?, h_entryBuf[0]));
					h_entryBuf[0] <= tagged Invalid;
				end
				else begin
					newEntryBuf.enq(h_ktEntryStream.first);
					h_ktEntryStream.deq;
				end

				if (h_curEntSzInBeats == 1) begin
					h_ktBeatCntStream.deq;
					mergedSizeInfo.enq(tagged Valid h_curEntSzInBeats);
				end
				else begin
					curMStatus <= HIGH_FLUSH;
					h_entryBeatSent <= 1;
				end

				if ( !l_moreBeat ) begin // EQUAL
					// remove low level entry @ [1]
					// Collect addresses for GC here
					if(!isValid(l_entryBuf[decPhaseCnt])) begin
						l_ktEntryStream.deq;
					end
					l_ktBeatCntStream.deq;
					writeVReg(l_entryBuf, replicate(tagged Invalid));

					if(collectedAddrQ.notFull) begin // if full, just drop (OKAY to drop i guess...)
						if(isValid(l_entryBuf[0])) begin
							collectedAddrQ.enq(truncate(fromMaybe(?, l_entryBuf[0])));
						end
						else begin
							collectedAddrQ.enq(truncate(l_ktEntryStream.first));
						end
					end
				end
				else begin
				end
			end
		end
	endrule

	rule h_flushEntry (curMStatus == HIGH_FLUSH);
		if (isValid(h_entryBuf[h_entryBeatSent])) begin
			newEntryBuf.enq(fromMaybe(?, h_entryBuf[h_entryBeatSent]));
			h_entryBuf[h_entryBeatSent] <= tagged Invalid;
		end
		else begin
			newEntryBuf.enq(h_ktEntryStream.first);
			h_ktEntryStream.deq;
		end

		let curEntSzInBeats = fromMaybe(?, h_ktBeatCntStream.first);
		if (zeroExtend(h_entryBeatSent) < curEntSzInBeats - 1) begin
			h_entryBeatSent <= h_entryBeatSent + 1;
		end
		else if (zeroExtend(h_entryBeatSent) >= curEntSzInBeats - 1) begin
			h_entryBeatSent <= 0;
			curMStatus <= DECISION;
			h_ktBeatCntStream.deq;
			mergedSizeInfo.enq(tagged Valid curEntSzInBeats);
		end
	endrule

	rule l_flushEntry (curMStatus == LOW_FLUSH);
		if (isValid(l_entryBuf[l_entryBeatSent])) begin
			newEntryBuf.enq(fromMaybe(?, l_entryBuf[l_entryBeatSent]));
			l_entryBuf[l_entryBeatSent] <= tagged Invalid;
		end
		else begin
			newEntryBuf.enq(l_ktEntryStream.first);
			l_ktEntryStream.deq;
		end

		let curEntSzInBeats = fromMaybe(?, l_ktBeatCntStream.first);
		if (zeroExtend(l_entryBeatSent) < curEntSzInBeats - 1) begin
			l_entryBeatSent <= l_entryBeatSent + 1;
		end
		else if (zeroExtend(l_entryBeatSent) >= curEntSzInBeats - 1) begin
			l_entryBeatSent <= 0;
			curMStatus <= DECISION;
			l_ktBeatCntStream.deq;
			mergedSizeInfo.enq(tagged Valid curEntSzInBeats);
		end
	endrule

	////////////////
	// CREATE HEADER
	////////////////
	Vector#(WordHeaderElems, Reg#(Bit#(HeaderElemSz))) newHeaderEntries <- replicateM(mkReg(0));
	Reg#(Bit#(16)) newHdrCnt <- mkReg(0);
	//Reg#(Bit#(16)) accumBeat <- mkReg(0);
	Reg#(Bit#(16)) ktOffset <- mkReg(0);

	FIFOF#(Bit#(WordSz)) newHeaderBuf <- mkSizedBRAMFIFOF(ktHeaderWords);
	FIFOF#(Tuple4#(Bool,Bit#(16), Bit#(16), Bit#(16))) newKtTrig <- mkFIFOF;

	rule newHeader;
		Bit#(16) sizeInByte = zeroExtend(fromMaybe(?, mergedSizeInfo.first)) << 4 ;

		if (isValid(mergedSizeInfo.first) && newHdrCnt == 0) begin
			newHeaderEntries[0] <= -1;   // to be updated later
			newHeaderEntries[1] <= 1024; // this field is always 1024
			newHeaderEntries[2] <= 1024 + sizeInByte;
			ktOffset <= 1024 + sizeInByte;
			newHdrCnt <= newHdrCnt + 3;
			mergedSizeInfo.deq;
		end
		else if (isValid(mergedSizeInfo.first) && ktOffset+sizeInByte <= 8192) begin

			newHeaderEntries[ newHdrCnt[2:0] ] <= ktOffset + sizeInByte;
			ktOffset <= ktOffset + sizeInByte;
			newHdrCnt <= newHdrCnt + 1;
			mergedSizeInfo.deq;

			if ( newHdrCnt[2:0] == 7 ) begin
				let vecHdr = readVReg(newHeaderEntries);
				vecHdr[7] = ktOffset + sizeInByte;
				newHeaderBuf.enq(pack(vecHdr));
			end
		end
		else begin
			newHdrCnt <= 0;

			if (newHdrCnt[2:0] != 0) begin
				Vector#(WordHeaderElems, Bit#(HeaderElemSz)) vecHdr = readVReg(newHeaderEntries);

				for(Integer i=0; i<8; i=i+1) begin
					if (newHdrCnt[2:0] <= fromInteger(i))
						vecHdr[i] = -1; // pad -1
				end
				newHeaderBuf.enq(pack(vecHdr));
			end

			if (isValid(mergedSizeInfo.first)) begin
				//(isLastKT, # of header beats pushed, lastKTEntry Offset, numEntries)
				newKtTrig.enq(tuple4(False, ((newHdrCnt-1)>>3) +1 , ktOffset, newHdrCnt-2));
			end
			else begin
				mergedSizeInfo.deq;
				//(isLastKT, # of header beats pushed, lastKTEntry Offset, numEntries)
				newKtTrig.enq(tuple4(True, ((newHdrCnt-1)>>3) +1 , ktOffset, newHdrCnt-2));
			end
		end
	endrule

	// Create Keytable
	// newEntryBuf, newHeaderBuf, newKtTrig
	// createdKtStream
	Reg#(Bit#(16)) outKtBeatCnt <- mkReg(0);
	rule newKT;
		if (outKtBeatCnt < fromInteger(ktHeaderWords)) begin // 64
			//if (outKtBeatCnt == 0) $display("[%d] table out start", cnt);

			if (outKtBeatCnt < tpl_2(newKtTrig.first)) begin
				newHeaderBuf.deq;
				let newHdr = newHeaderBuf.first;
				if (outKtBeatCnt == 0) begin
					newHdr[15:0] = tpl_4(newKtTrig.first);
				end
				createdKtStream.enq(tuple2(tpl_1(newKtTrig.first), newHdr));
			end
			else begin
				createdKtStream.enq(tuple2(tpl_1(newKtTrig.first), -1));
			end
			outKtBeatCnt <= outKtBeatCnt + 1;
		end
		else if (outKtBeatCnt < fromInteger(keytableWords)) begin // 512
			if (outKtBeatCnt < (tpl_3(newKtTrig.first)>>4)) begin
				newEntryBuf.deq;
				createdKtStream.enq(tuple2(tpl_1(newKtTrig.first), newEntryBuf.first));
			end
			else begin
				createdKtStream.enq(tuple2(tpl_1(newKtTrig.first), -1));
			end

			if(outKtBeatCnt == fromInteger(keytableWords)-1) begin
				outKtBeatCnt <= 0;
				// One page out..
				newKtTrig.deq;
				//$display("[%d] table out complete", cnt);
			end
			else begin
				outKtBeatCnt <= outKtBeatCnt + 1;
			end
		end
	endrule

	method Action runMerge(Bit#(32) numHighLvlKt, Bit#(32) numLowLvlKt) if (numKeytable[0] == 0 && numKeytable[1] == 0);
		numKeytable[0] <= numHighLvlKt;
		numKeytable[1] <= numLowLvlKt;
		numKeytableOrig[0] <= numHighLvlKt;
		numKeytableOrig[1] <= numLowLvlKt;
		keytableInBeat[0] <= 0;
		keytableInBeat[1] <= 0;
	endmethod

	method Action enqHighLevelKt(Bit#(WordSz) beat);
		keytableIn[0].enq(beat);
	endmethod
	method Action enqLowLevelKt(Bit#(WordSz) beat);
		keytableIn[1].enq(beat);
	endmethod

//	method MergerStatus mergerStatus();
//	endmethod

	method ActionValue#(Tuple2#(Bool,Bit#(WordSz))) getMergedKt();
		createdKtStream.deq;
		return createdKtStream.first;
	endmethod
	method ActionValue#(Bit#(32)) getCollectedAddr();
		collectedAddrQ.deq;
		return collectedAddrQ.first;
	endmethod
endmodule
