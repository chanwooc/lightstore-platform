import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import BRAM::*;
import BRAMFIFO::*;

import Ehr::*;

import GetPut::*;
import ClientServer::*;
import Connectable::*;
import DefaultValue::*;

import Vector::*;

import ControllerTypes::*;
import DualFlashTypes::*;

import Clocks::*;

import AFTL_Types::*;

Bool verbose = False;

// ***********
// Module Design
// ***********
typedef enum {
	AftlREAD = 0,
	AftlWRITE,
	AftlERASE,
	AftlMARKBAD,
	AftlINVALID
} AftlCmdTypes deriving (Bits, Eq, FShow);

typedef struct {
	TagT tag;
	AftlCmdTypes cmd;
	LPA lpa;
} FTLCmd deriving (Bits, Eq);

interface AFTLIfc;
	interface Put#(FTLCmd) translateReq;
	interface Get#(DualFlashCmd) resp;
	interface Get#(FTLCmd) respError;

	interface BRAMServer#(BlockMapAddr, MapEntry) map_portB;
	interface BRAMServer#(BlkInfoTblAddr, Vector#(BlkInfoEntriesPerWord, BlkInfoEntry)) blkinfo_portB;

	// method Action eraseAckFromFlash(Tuple2#(TagT, Bool) a);
	// method ActionValue#(Tuple2#(TagT, Bool)) eraseAckToHost;
endinterface

(* synthesize *)
module mkAFTLBRAM128 (AFTLIfc);
	let _m <- mkAFTL(True, 128);
	return _m;
endmodule

(* synthesize *)
module mkAFTL128 (AFTLIfc);
	let _m <- mkAFTL(False, 128);
	return _m;
endmodule

typedef struct {
	LPA lpa;
	DualFlashCmd cmd;
} LPA_DualFlashCmd deriving (Bits, Eq);

module mkAFTL#(Bool isReqBramQ, Integer cmdQDepth)(AFTLIfc);

	FIFO#(FTLCmd) reqQ;
	if (isReqBramQ)
		reqQ <- mkSizedBRAMFIFO(cmdQDepth);
	else
		reqQ <- mkSizedFIFO(cmdQDepth);

	FIFO#(DualFlashCmd) respQ <- mkFIFO;
	FIFO#(DualFlashCmd) respQ_pre <- mkFIFO;
	FIFO#(FTLCmd) resp_errorQ <- mkFIFO;

	// ** Mapping Table **
	//   addr: {Segment #, Virt Blk #}
	//   data: MapEntry{ 2-bit MapStatus, 14-bit Mapped Physical Block # }
	BRAM_Configure map_conf = defaultValue;
	map_conf.latency = 2; // output register; TODO: 2-cycle latency for reads; better timing?
	map_conf.outFIFODepth = 4;
	BRAM2Port#(BlockMapAddr, MapEntry) blockmap <- mkBRAM2Server(map_conf);

	// ** Block Info Table **
	//   addr: {Card, Bus, Chip, Block} >> BlkInfoSelSz;
	//   data: BlkInfoEntriesPerWord * BlkInfoEntry{ 2-bit BlkStatus, 14-bit PE }
	BRAM_Configure blk_conf = defaultValue;
	blk_conf.latency = 2; // output register; TODO: 2-cycle latency for reads; better timing?
	blk_conf.outFIFODepth = 4;
	BRAM2Port#(BlkInfoTblAddr, Vector#(BlkInfoEntriesPerWord, BlkInfoEntry)) blkinfo <- mkBRAM2Server(blk_conf);
	// BRAM2PortBE#(Bit#(TSub#(TAdd#(SegmentTSz, VirtBlkTSz), BlkInfoSelSz)), Vector#(BlkInfoEntriesPerWord, BlkInfoEntry), TDiv#(TMul#(SizeOf#(BlkInfoEntry), BlkInfoEntriesPerWord), 8)) blkinfo <- mkBRAM2ServerBE(blk_conf);

	// FIFO#(FTLCmd) procQ <- mkPipelinedFIFO; // Size == 1, Only 1 req in-flight
	// FIFOF#(FTLCmd) procQ <- mkFIFOF1; // Size == 1, Only 1 req in-flight

	FIFOF#(FTLCmd) procQ <- mkFIFOF; 
	FIFOF#(LPA_DualFlashCmd) procQ_R <- mkFIFOF;
	FIFOF#(LPA_DualFlashCmd) procQ_W <- mkFIFOF;
	FIFOF#(LPA_DualFlashCmd) procQ_W_trig <- mkFIFOF;
	FIFOF#(LPA_DualFlashCmd) procQ_E <- mkFIFOF;
	FIFOF#(LPA_DualFlashCmd) procQ_MB <- mkFIFOF;

	Vector#(6,FIFOF#(Tuple2#(Bit#(2), LPA_DualFlashCmd))) procUpdateQs <- replicateM(mkFIFOF);


	Reg#(Bool) inProgress <- mkReg(False);

	Reg#(Bit#(32)) cnt <- mkReg(0);
	rule cntup;
		cnt <= cnt+1;
	endrule

	rule routeRespQ;
		let d <- toGet(respQ_pre).get;
		respQ.enq(d);
	endrule

	rule requestMapping ( inProgress == False );
		if(verbose) $display("[%d] requestMapping", cnt);

		let ftlCmd <- toGet(reqQ).get;

		case(ftlCmd.cmd)
			AftlWRITE, AftlREAD, AftlERASE, AftlMARKBAD: begin
				procQ.enq( ftlCmd );
				let addr = { getSegmentT(ftlCmd.lpa), getVirtBlkT(ftlCmd.lpa) };
				inProgress <= True;

				blockmap.portA.request.put (
					BRAMRequest{write: False, responseOnWrite: False, address: addr, datain: ?}
				);
			end

			default: begin
				resp_errorQ.enq( ftlCmd );
			end
		endcase
	endrule

	rule checkMapping0 (inProgress);
		if(verbose) $display("[%d] checkMapping0", cnt);

		let mapEntry <- blockmap.portA.response.get;
		let lpa = procQ.first.lpa;

		FlashOp op = INVALID;
		case (procQ.first.cmd)
			AftlWRITE: op = WRITE_PAGE;
			AftlREAD:  op = READ_PAGE;
			AftlERASE: op = ERASE_BLOCK;
		endcase

		let oneFlashCmd = FlashCmd {
			tag: procQ.first.tag,
			op: op,
			bus: truncate( lpa >> valueOf(TLog#(NUM_CARDS)) ),
			chip: truncate( {getSegmentT(lpa), getVirtBlkT(lpa)} >> valueOf(TLog#(TMul#(NUM_BUSES, NUM_CARDS))) ),
			block: zeroExtend( mapEntry.block ),
			page: zeroExtend( getPageT(lpa) )
		};

		let multiFlashCmd = DualFlashCmd{
			card: lpa[0], // IF one card, could be wrong value but ignored
			fcmd: oneFlashCmd
		};

		procQ.deq;
		case (mapEntry.status)
			ALLOCATED: begin
				case (procQ.first.cmd)
					AftlREAD:   procQ_R.enq(LPA_DualFlashCmd{lpa: lpa, cmd: multiFlashCmd});
					AftlWRITE:  procQ_W.enq(LPA_DualFlashCmd{lpa: lpa, cmd: multiFlashCmd});
					AftlERASE: procQ_E.enq(LPA_DualFlashCmd{lpa: lpa, cmd: multiFlashCmd});
					AftlMARKBAD: procQ_MB.enq(LPA_DualFlashCmd{lpa: lpa, cmd: multiFlashCmd});
				endcase
			end

			NOT_ALLOCATED: begin
				case (procQ.first.cmd)
					AftlREAD, AftlERASE: begin
						resp_errorQ.enq(procQ.first);
					end
					AftlWRITE: procQ_W_trig.enq(LPA_DualFlashCmd{lpa: lpa, cmd: multiFlashCmd});
					AftlMARKBAD: procQ_MB.enq(LPA_DualFlashCmd{lpa: lpa, cmd: multiFlashCmd});
				endcase
			end

			default: begin
				resp_errorQ.enq(procQ.first);
			end
		endcase
	endrule

	rule procAftlRead (inProgress);
		procQ_R.deq;
		respQ.enq(procQ_R.first.cmd);
	endrule

	(* descending_urgency = "routeRespQ, procAftlRead, procAftlWriteAllocated" *)
	rule procAftlWriteAllocated (inProgress);
		procQ_W.deq;
		respQ.enq(procQ_W.first.cmd);
	endrule

	(* descending_urgency = "procAftlMarkBadBlock, procAftlErase, procAftlWriteNotAllocated" *) // urgency for procUpdateQs[0]

	rule procAftlMarkBadBlock (inProgress);
		procQ_MB.deq;
		procUpdateQs[0].enq(tuple2(0, procQ_MB.first));
	endrule

	rule procAftlErase (inProgress);
		procQ_E.deq;

		let cmd = procQ_E.first.cmd;
		cmd.fcmd.page = 0;

		procUpdateQs[0].enq(tuple2(1, LPA_DualFlashCmd{lpa: procQ_E.first.lpa, cmd: cmd}));
	endrule

	rule procAftlWriteNotAllocated (inProgress);
		procQ_W_trig.deq;

		procUpdateQs[0].enq(tuple2(2, procQ_W_trig.first));
	endrule

	let isQ0Erase = (tpl_1(procUpdateQs[0].first) <= 1);

	Reg#(Bit#(TAdd#(1, TSub#(BlockTSz, BlkInfoSelSz)))) blkScanReqCnt <- mkReg(0);
	Reg#(Bit#(TAdd#(1, TSub#(BlockTSz, BlkInfoSelSz)))) blkScanRespCnt <- mkReg(0);
	Reg#(Bit#(TAdd#(1, BlkInfoSelSz))) blkScanFinalCnt <- mkReg(0);
	Bit#(TAdd#(1, TSub#(BlockTSz, BlkInfoSelSz))) max_block_scan_req = fromInteger(valueOf(TExp#(TSub#(BlockTSz, BlkInfoSelSz))));

	Reg#(Bool) blkScanIssued <- mkReg(False);

	rule updateBlkInfo0 (inProgress && blkScanIssued == False);
		if(verbose) $display("[%d] updateBlkInfo0", cnt);

		if (isQ0Erase) begin
			// Erase command
			// Skip [0,1,2] and goto [3]
			let procCmd <- toGet(procUpdateQs[0]).get;
			procUpdateQs[3].enq(procCmd);
			blkScanIssued <= True; // mark as if blk (skipping [0,1])
		end
		else begin
			// Write command (New allocation)
			if( blkScanReqCnt == 0 ) begin
				blkScanReqCnt <= blkScanReqCnt + 1;
				procUpdateQs[1].enq(procUpdateQs[0].first);
			end
			else if( blkScanReqCnt == max_block_scan_req - 1 ) begin
				blkScanReqCnt <= 0;
				procUpdateQs[0].deq;
				blkScanIssued <= True;
			end
			else begin
				blkScanReqCnt <= blkScanReqCnt + 1;
			end

			let curCmd = tpl_2(procUpdateQs[0].first).cmd;

			BusT bus = curCmd.fcmd.bus;
			ChipT chip = curCmd.fcmd.chip;
			Bit#(TSub#(BlockTSz, BlkInfoSelSz)) block_upper = truncate(blkScanReqCnt);

			BlkInfoTblAddr addr = 
					truncate({curCmd.card, bus, chip, block_upper});

			blkinfo.portA.request.put (
				BRAMRequest{write: False, responseOnWrite: False, address: addr, datain: ?}
			);
		end
	endrule

	function Maybe#(Tuple2#(Bit#(14), Bit#(14))) updateMinEntries (Maybe#(Tuple2#(Bit#(14), Bit#(14))) prevMin, BlkInfoEntry blkEntry, Integer idx);
		if (blkEntry.status != FREE_BLK)
			return prevMin;
		else begin
			//compare only if FREE_BLK
			Bit#(14) minBlk = (zeroExtend( blkScanRespCnt ) << valueOf(BlkInfoSelSz)) + fromInteger(idx);
			//if(verbose) $display("[func] ");
			case ( isValid(prevMin) && tpl_2(fromMaybe(?, prevMin)) <= blkEntry.erase )
				True:  return prevMin;
				False: return tagged Valid tuple2( minBlk , blkEntry.erase);
			endcase
		end
	endfunction

	function Maybe#(Tuple2#(Bit#(14), Bit#(14))) getMinEntries (Maybe#(Tuple2#(Bit#(14), Bit#(14))) prevMin, Maybe#(Tuple2#(Bit#(14), Bit#(14))) nextMin);
		if (isValid (nextMin)) begin
			if (isValid(prevMin)) begin
				return (tpl_2(fromMaybe(?, prevMin))<=tpl_2(fromMaybe(?, nextMin)))?prevMin:nextMin;
			end
			else begin
				return nextMin;
			end
		end
		else begin
			return prevMin;
		end
	endfunction

	// <blk_num, pe cnt> pair
	Reg#(Vector#(BlkInfoEntriesPerWord, Maybe#(Tuple2#(Bit#(14), Bit#(14))))) curMinEnt <- mkReg(replicate(tagged Invalid));
	FIFO#(Vector#(BlkInfoEntriesPerWord, Maybe#(Tuple2#(Bit#(14), Bit#(14))))) minEntVecQ <- mkFIFO;

	// WRITE command only: miss AFTL -> new allocation
	// SCAN available block with minimum PE
	rule updateBlkInfo1 (inProgress && procUpdateQs[1].notEmpty);
		if(verbose) $display("[%d] updateBlkInfo1", cnt);
		let d <- blkinfo.portA.response.get;

		//$display("dd: %x %x %x %x", d[3], d[2], d[1], d[0]);
		//$display("c1: %x %x %x %x", tpl_1(fromMaybe(?,curMinEnt[3])), tpl_1(fromMaybe(?,curMinEnt[2])), tpl_1(fromMaybe(?,curMinEnt[1])), tpl_1(fromMaybe(?,curMinEnt[0])));
		//$display("c2: %x %x %x %x", tpl_2(fromMaybe(?,curMinEnt[3])), tpl_2(fromMaybe(?,curMinEnt[2])), tpl_2(fromMaybe(?,curMinEnt[1])), tpl_2(fromMaybe(?,curMinEnt[0])));
		//$display("v: %x %x %x %x", isValid(curMinEnt[3]), isValid(curMinEnt[2]), isValid(curMinEnt[1]), isValid(curMinEnt[0]) );

		let newMinEnt = zipWith3( updateMinEntries, curMinEnt, d, genVector() );

		if( blkScanRespCnt == max_block_scan_req - 1 ) begin
			blkScanRespCnt <= 0;

			curMinEnt <= replicate(tagged Invalid);


			minEntVecQ.enq(newMinEnt);
			//$display("v: %x %x %x %x", isValid(curMinEnt[3]), isValid(curMinEnt[2]), isValid(curMinEnt[1]), isValid(curMinEnt[0]) );
			//$display("c1: %x %x %x %x", tpl_1(fromMaybe(?,curMinEnt[3])), tpl_1(fromMaybe(?,curMinEnt[2])), tpl_1(fromMaybe(?,curMinEnt[1])), tpl_1(fromMaybe(?,curMinEnt[0])));
			//$display("c2: %x %x %x %x", tpl_2(fromMaybe(?,curMinEnt[3])), tpl_2(fromMaybe(?,curMinEnt[2])), tpl_2(fromMaybe(?,curMinEnt[1])), tpl_2(fromMaybe(?,curMinEnt[0])));

			let procCmd <- toGet(procUpdateQs[1]).get;
			procUpdateQs[2].enq(procCmd);
		end
		else begin
			blkScanRespCnt <= blkScanRespCnt + 1;
			curMinEnt <= newMinEnt;
		end
	endrule

	Reg#(Vector#(BlkInfoEntriesPerWord, Maybe#(Tuple2#(Bit#(14), Bit#(14))))) minEnt <- mkReg(replicate(tagged Invalid));
	Reg#(Maybe#(Tuple2#(Bit#(14), Bit#(14)))) theMinEntry <- mkReg(tagged Invalid);
	FIFO#(Tuple2#(Bit#(14), Bit#(14))) minPeEntryQ <- mkFIFO;

	// WRITE command only: miss AFTL -> new allocation
	// SCAN continued (final processing)
	(* descending_urgency = "checkMapping0, updateBlkInfo0, updateBlkInfo2" *) // urgency for resp_errorQ & procUpdateQs[3]
	rule updateBlkInfo2 (inProgress && procUpdateQs[2].notEmpty);
		if(verbose) $display("[%d] updateBlkInfo2", cnt);
		if (blkScanFinalCnt == 0) begin
			blkScanFinalCnt <= blkScanFinalCnt + 1 ;

			let v = minEntVecQ.first[0];
			minEntVecQ.deq;

			minEnt <= rotate(minEntVecQ.first);
			theMinEntry <= getMinEntries(theMinEntry, v);
		end
		else if (blkScanFinalCnt == fromInteger(valueOf(BlkInfoEntriesPerWord)-1)) begin
			blkScanFinalCnt <= 0;

			minEnt <= replicate(tagged Invalid);
			theMinEntry <= tagged Invalid;


			let finalEntry = getMinEntries(theMinEntry, minEnt[0]);
			if (isValid(finalEntry)) begin
				minPeEntryQ.enq(fromMaybe(?, finalEntry));

				//$display("final entry: %d %d", tpl_1(fromMaybe(?, finalEntry)), tpl_2(fromMaybe(?, finalEntry)));

				let procCmd <- toGet(procUpdateQs[2]).get;
				procUpdateQs[3].enq(procCmd);
			end
			else begin
				let procCmd <- toGet(procUpdateQs[2]).get;

				let fcmd = tpl_2(procUpdateQs[2].first).cmd.fcmd;

				FTLCmd resp_err
					= FTLCmd{ tag: fcmd.tag, cmd: AftlWRITE, lpa: tpl_2(procUpdateQs[2].first).lpa };

				resp_errorQ.enq(resp_err);
			end
		end
		else begin
			blkScanFinalCnt <= blkScanFinalCnt + 1 ;

			minEnt <= rotate(minEnt);
			theMinEntry <= getMinEntries(theMinEntry, minEnt[0]);
		end
	endrule

	let isQ3Erase = (tpl_1(procUpdateQs[3].first) <= 1);
	// WRITE & ERASE
	// Update BlkInfo - first read the line
	rule updateBlkInfo3 (inProgress && blkScanIssued == True);
		if(verbose) $display("[%d] updateBlkInfo3", cnt);
		let curCmd = tpl_2(procUpdateQs[3].first).cmd;
		let curLPA = tpl_2(procUpdateQs[3].first).lpa;

		if(!isQ3Erase) curCmd.fcmd.block = zeroExtend(tpl_1(minPeEntryQ.first));

		procUpdateQs[3].deq;
		procUpdateQs[4].enq(tuple2(tpl_1(procUpdateQs[3].first), LPA_DualFlashCmd{lpa: curLPA, cmd: curCmd} ));

		BusT bus = curCmd.fcmd.bus;
		ChipT chip = curCmd.fcmd.chip;
		BlockT block = truncate(curCmd.fcmd.block);

		BlkInfoTblAddr addr =
			truncate({curCmd.card, bus, chip, block} >> valueOf(BlkInfoSelSz));

		//$display("updateBlkinfo3 addr %d", addr);

		blkinfo.portA.request.put (
			BRAMRequest{write: False, responseOnWrite: False, address: addr, datain: ?}
		);
	endrule

	function BlkInfoEntry eraseBlkInfoEntry( BlkInfoEntry entry );
		return BlkInfoEntry{status: FREE_BLK, erase: entry.erase+1};
	endfunction

	function BlkInfoEntry markBadEntry( BlkInfoEntry entry );
		return BlkInfoEntry{status: BAD_BLK, erase: entry.erase};
	endfunction

	function BlkInfoEntry muxBlkInfoEntry( Bit#(1) sel, BlkInfoEntry a0, BlkInfoEntry a1 );
		return sel==0?a0:a1;
	endfunction

	let typeQ4 = tpl_1(procUpdateQs[4].first);

	(* descending_urgency = "updateBlkInfo4, updateBlkInfo3, updateBlkInfo1" *)
	rule updateBlkInfo4 (inProgress && blkScanIssued == True);
		if(verbose) $display("[%d] updateBlkInfo4", cnt);
		let procCmd <- toGet(procUpdateQs[4]).get;
		procUpdateQs[5].enq(procCmd);

		let blkinfo_vec <- blkinfo.portA.response.get;

		let curCmd = tpl_2(procUpdateQs[4].first).cmd;

		//Vector#(BlkInfoEntriesPerWord, BlkInfoEntry) new_line;

		BusT bus = curCmd.fcmd.bus;
		ChipT chip = curCmd.fcmd.chip;
		BlockT block = truncate(curCmd.fcmd.block);
		BlkInfoSelT block_lower = truncate(block);

		BlkInfoTblAddr addr =
			truncate({curCmd.card, bus, chip, block} >> valueOf(BlkInfoSelSz));

		if (typeQ4 <= 1) begin
			let blkinfo_vec_erased = map(eraseBlkInfoEntry, blkinfo_vec);
			if (typeQ4 == 0) blkinfo_vec_erased = map(markBadEntry, blkinfo_vec);

			Bit#(BlkInfoEntriesPerWord) sel_vec = 1 << block_lower;

			blkinfo_vec = zipWith3(muxBlkInfoEntry, unpack(sel_vec), blkinfo_vec, blkinfo_vec_erased);
		end
		else begin
			let updatedEntry = BlkInfoEntry{status: USED_BLK, erase: tpl_2(minPeEntryQ.first)};
			minPeEntryQ.deq;
			blkinfo_vec[block_lower] = updatedEntry;
			//$display("updateBlkinfo4 addr %d", addr);
			//$display("updateBlkIfo4 %x %x %x %x %x", blkinfo_vec[7], blkinfo_vec[3], blkinfo_vec[2], blkinfo_vec[1], blkinfo_vec[0]);
		end

		blkinfo.portA.request.put (
			BRAMRequest{ write: True, responseOnWrite: False, address: truncate(addr), datain: blkinfo_vec}
		);

	endrule

	let typeQ5 = tpl_1(procUpdateQs[5].first);

	FIFO#(Bit#(1)) markBadDoneQ <- mkFIFO;

	rule updateBlkInfo5 (inProgress && blkScanIssued == True);
		if(verbose) $display("[%d] updateBlkInfo5", cnt);
		blkScanIssued <= False;

		let cmd = tpl_2(procUpdateQs[5].first).cmd;
		let lpa = tpl_2(procUpdateQs[5].first).lpa;

		procUpdateQs[5].deq;

		let addr_blkmap = { getSegmentT(lpa), getVirtBlkT(lpa) };

		if(typeQ5 == 0) begin
			markBadDoneQ.enq(?);
		end
		else begin
			respQ_pre.enq(cmd);
		end

		BlockT block = truncate(cmd.fcmd.block);
		let entry = MapEntry{status: (typeQ5<=1)?NOT_ALLOCATED:ALLOCATED, block: zeroExtend(block)};

		blockmap.portA.request.put ( 
			BRAMRequest{write: True, responseOnWrite: False, address: addr_blkmap, datain: entry}
		);
	endrule

	Wire#(Bit#(1)) blockResp <- mkDWire(0);

	rule drainMarkBadDone (inProgress);
		markBadDoneQ.deq;
		blockResp <= 1;
		inProgress <= False;
	endrule

	interface translateReq = toPut(reqQ);
	interface Get resp;
		method ActionValue#(DualFlashCmd) get if (inProgress && blockResp == 0);
			let d <- toGet(respQ).get;
			inProgress <= False;
			return d;
		endmethod
	endinterface
	interface Get respError;
		method ActionValue#(FTLCmd) get if (inProgress && blockResp == 0);
			let d <- toGet(resp_errorQ).get;
			inProgress <= False;
			return d;
		endmethod
	endinterface
	interface map_portB = blockmap.portB;
	interface blkinfo_portB = blkinfo.portB;
endmodule
