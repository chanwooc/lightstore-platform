import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import BRAM::*;
import BRAMFIFO::*;

import GetPut::*;
import ClientServer::*;
import Connectable::*;
import DefaultValue::*;

import Vector::*;

import ControllerTypes::*;
import MyTypes::*;

import Clocks::*;

Bool verbose = False;

// ** LPA Structure **
//   Virtual Block # format:
//      [ Chip # lower N-bit ][ Bus # ][ Card # ]
//
//   Segment # format:
//      [ LPA MSBits ... ][ Chip # upper (K-N)-bit ]
//      where K is number of total bits needed to encode chip #
//            N is number of lower bits used to encode virtual block #
//      Total number of segments: (Number of Physical Block per Chip) * 2^(K-N)
//
//   LPA fields:
//      [ segment # ][ page # ][ virt blk # ]
//      Length: Sum of bits required to encode Card / Bus / Chip / Blk / Page
//
// Types 
// 1. Define "N"  (K defined as ChipsPerBus in ControllerTypes.bsv)
// 2. LPA component Bit-Width (TSz) and Bit Type (T)

`ifdef BSIM
typedef 3 ChipBitsInVirtBlk; // K = 8
`elsif SLC
typedef 2 ChipBitsInVirtBlk; // K = 4
`else
typedef 3 ChipBitsInVirtBlk; // K = 8
`endif

typedef TMul#(BlocksPerCE, TExp#(TSub#(TLog#(ChipsPerBus), ChipBitsInVirtBlk))) NumSegments;
typedef TMul#(TExp#(ChipBitsInVirtBlk), TMul#(NUM_BUSES, NUM_CARDS)) VirtBlksPerSegment;

typedef TLog#(VirtBlksPerSegment) VirtBlkTSz;
typedef TLog#(PagesPerBlock) PageTSz;
typedef TLog#(NumSegments) SegmentTSz;

typedef Bit#(VirtBlkTSz) VirtBlkT;
typedef Bit#(PageTSz) PageT;
typedef Bit#(SegmentTSz) SegmentT;
typedef Bit#(TAdd#(VirtBlkTSz, TAdd#(PageTSz, SegmentTSz))) LPA;

// type for flash block
typedef TLog#(BlocksPerCE) BlockTSz;
typedef Bit#(BlockTSz) BlockT;

function VirtBlkT getVirtBlkT(LPA lpa);
	return truncate( lpa );
endfunction

function PageT getPageT(LPA lpa);
	return truncate( lpa >> valueOf(VirtBlkTSz) );
endfunction

function SegmentT getSegmentT(LPA lpa);
	return truncate( lpa >> valueOf(TAdd#(PageTSz, VirtBlkTSz)) );
endfunction

// ** Mapping Table **
//   input: {Segment #, Virt Blk #}
//   output: MapEntry{ 2-bit MapStatus, 14-bit Mapped Physical Block # }

`ifndef BSIM
// DRAM FFFF
// BRAM 0000
// typedef enum { NOT_ALLOCATED, ALLOCATED, DEAD } MapStatus deriving (Bits, Eq);
typedef enum { DEAD, ALLOCATED, NOT_ALLOCATED } MapStatus deriving (Bits, Eq);
`else
// For testing. At BSIM, RAM is initialized to AAAAAAA
typedef enum { DEAD, ALLOCATED, NOT_ALLOCATED } MapStatus deriving (Bits, Eq);
`endif

typedef struct {
	MapStatus status; // FIXME: DEAD not used
	Bit#(TSub#(16, SizeOf#(MapStatus))) block; // physical block#
} MapEntry deriving (Bits, Eq); // 16-bit (2-bytes) mapping entry


// ** Physical Block Information Table **
//   input: Physical {Card, Bus, Chip, Block}
//   output: BlkInfoEntry{ 2-bit BlkStatus, 14-bit P/E count }

`ifndef BSIM
// DRAM FFFF
// BRAM 0000
// typedef enum { FREE_BLK, DIRTY_BLK, CLEAN_BLK, BAD_BLK } BlkStatus deriving (Bits, Eq);
typedef enum { BAD_BLK, DIRTY_BLK, FREE_BLK, CLEAN_BLK } BlkStatus deriving (Bits, Eq);
`else
// For testing. At BSIM, RAM is initialized to AAAAAAA
typedef enum { BAD_BLK, DIRTY_BLK, FREE_BLK, CLEAN_BLK } BlkStatus deriving (Bits, Eq);
`endif

typedef struct {
	BlkStatus status; //2
	Bit#(TSub#(16, SizeOf#(BlkStatus))) erase; //14
} BlkInfoEntry deriving (Bits, Eq); // 16-bit (2-bytes) block info entry

typedef 16 BlkInfoEntriesPerWord;
typedef TLog#(BlkInfoEntriesPerWord) BlkInfoSelSz;
typedef Bit#(BlkInfoSelSz) BlkInfoSelT;

// ***********
// Module Design
// ***********

typedef struct {
	TagT tag;
	FlashOp op;
	LPA lpa;
} FTLCmd deriving (Bits, Eq);

interface AFTLIfc;
	interface Put#(FTLCmd) translateReq;
	interface Get#(MultiFlashCmd) resp;
	interface Get#(FTLCmd) respError;

	interface BRAMServer#(Bit#(TAdd#(SegmentTSz, VirtBlkTSz)), MapEntry) map_portB;
	interface BRAMServer#(Bit#(TSub#(TAdd#(SegmentTSz, VirtBlkTSz), BlkInfoSelSz)), Vector#(BlkInfoEntriesPerWord, BlkInfoEntry)) blkinfo_portB;

	// method Action eraseAckFromFlash(Tuple2#(TagT, Bool) a);
	// method ActionValue#(Tuple2#(TagT, Bool)) eraseAckToHost;
endinterface

(* synthesize *)
module mkAFTL128 (AFTLIfc);
	let _m <- mkAFTL(128);
	return _m;
endmodule

module mkAFTL#(Integer cmdQDepth)(AFTLIfc);
	FIFO#(FTLCmd) reqQ <- mkSizedFIFO(cmdQDepth);
	FIFO#(MultiFlashCmd) respQ <- mkFIFO;
	FIFO#(FTLCmd) resp_errorQ <- mkFIFO;

	// ** Mapping Table **
	//   addr: {Segment #, Virt Blk #}
	//   data: MapEntry{ 2-bit MapStatus, 14-bit Mapped Physical Block # }
	BRAM_Configure map_conf = defaultValue;
	// map_conf.latency = 2; // output register; TODO: 2-cycle latency for reads; better timing?
	// map_conf.outFIFODepth = 4;
	BRAM2Port#(Bit#(TAdd#(SegmentTSz, VirtBlkTSz)), MapEntry) map <- mkBRAM2Server(map_conf);

	// ** Block Info Table **
	//   addr: {Card, Bus, Chip, Block} >> BlkInfoSelSz;
	//   data: BlkInfoEntriesPerWord * BlkInfoEntry{ 2-bit BlkStatus, 14-bit PE }
	BRAM_Configure blk_conf = defaultValue;
	// blk_conf.latency = 2; // output register; TODO: 2-cycle latency for reads; better timing?
	// blk_conf.outFIFODepth = 4;
	BRAM2Port#(Bit#(TSub#(TAdd#(SegmentTSz, VirtBlkTSz), BlkInfoSelSz)), Vector#(BlkInfoEntriesPerWord, BlkInfoEntry)) blkinfo <- mkBRAM2Server(blk_conf);
	// BRAM2PortBE#(Bit#(TSub#(TAdd#(SegmentTSz, VirtBlkTSz), BlkInfoSelSz)), Vector#(BlkInfoEntriesPerWord, BlkInfoEntry), TDiv#(TMul#(SizeOf#(BlkInfoEntry), BlkInfoEntriesPerWord), 8)) blkinfo <- mkBRAM2ServerBE(blk_conf);

	//FIFO#(FTLCmd) procQ <- mkPipelinedFIFO; // Size == 1, Only 1 req in-flight
	FIFOF#(FTLCmd) procQ <- mkFIFOF1; // Size == 1, Only 1 req in-flight

	Reg#(Bit#(32)) cnt <- mkReg(0);
	rule cntup;
		cnt <= cnt+1;
	endrule

	rule requestReadMap (!procQ.notEmpty); // do only if the procQ is empty (strict guard for conflicts)
		if(verbose) $display("reqReadMap, %d", cnt);
		let ftlCmd <- toGet(reqQ).get;

		case(ftlCmd.op)
			WRITE_PAGE, READ_PAGE, ERASE_BLOCK: begin
				procQ.enq( ftlCmd );
				let addr = { getSegmentT(ftlCmd.lpa), getVirtBlkT(ftlCmd.lpa) };

				map.portA.request.put (
					BRAMRequest{write: False, responseOnWrite: False, address: addr, datain: ?}
				);
			end

			default: begin
				resp_errorQ.enq( ftlCmd );
			end
		endcase
	endrule

	rule procMapFlashRead ( procQ.first.op == READ_PAGE );
		if(verbose) $display("procMapRead, %d", cnt);
		let mapEntry <- map.portA.response.get;
		let lpa = procQ.first.lpa;

		case (mapEntry.status)
			ALLOCATED: begin
				let oneFlashCmd = FlashCmd {
					tag: procQ.first.tag,
					op: READ_PAGE,
					bus: truncate( lpa >> valueOf(TLog#(NUM_CARDS)) ),
					chip: truncate( {getSegmentT(lpa), getVirtBlkT(lpa)} >> valueOf(TLog#(TMul#(NUM_BUSES, NUM_CARDS))) ),
					block: zeroExtend( mapEntry.block ),
					page: zeroExtend( getPageT(lpa) )
				};

				let multiFlashCmd = MultiFlashCmd{
					card: lpa[0], // IF one card, could be wrong value but ignored
					fcmd: oneFlashCmd
				};

				procQ.deq;
				respQ.enq(multiFlashCmd);
			end
			default: begin
				procQ.deq;
				resp_errorQ.enq(procQ.first);
			end
		endcase
	endrule

	Reg#(Bit#(2)) phaseErase <- mkReg(0);
	Reg#(MultiFlashCmd) curEraseCmd <- mkRegU;

	rule procMapFlashErase0 ( procQ.first.op == ERASE_BLOCK && phaseErase == 0 );
		if(verbose) $display("erase0, %d", cnt);
		let mapEntry <- map.portA.response.get;
		let lpa = procQ.first.lpa;

		let oneFlashCmd = FlashCmd {
			tag: procQ.first.tag,
			op: ERASE_BLOCK,
			bus: truncate( lpa >> valueOf(TLog#(NUM_CARDS)) ),
			chip: truncate( {getSegmentT(lpa), getVirtBlkT(lpa)} >> valueOf(TLog#(TMul#(NUM_BUSES, NUM_CARDS))) ),
			block: zeroExtend( mapEntry.block ),
			page: 0
		};

		let multiFlashCmd = MultiFlashCmd{
			card: lpa[0], // IF one card, could be wrong value but ignored
			fcmd: oneFlashCmd
		};

		case (mapEntry.status)
			ALLOCATED: begin
				respQ.enq(multiFlashCmd);

				// Update block map -> NOT_ALLOCATED
				//  This should be visible to the very next cmd in req -> procQ should be mkFIFO1
				let addr = { getSegmentT(procQ.first.lpa), getVirtBlkT(procQ.first.lpa) };
				map.portA.request.put ( 
					BRAMRequest{write: True, responseOnWrite: False, address: addr, datain: MapEntry{status: NOT_ALLOCATED, block: 0}}
				);

				// Move to update PE count..
				phaseErase <= 1;
				curEraseCmd <= multiFlashCmd;
			end
			default: begin
				procQ.deq;
				resp_errorQ.enq(procQ.first);
			end
		endcase
	endrule

	rule procMapFlashErase1 ( procQ.first.op == ERASE_BLOCK && phaseErase == 1 );
		if(verbose) $display("erase1, %d", cnt);
		// card (optional, will be truncated if one card), bus, chip, block_upper bits
		BusT bus = curEraseCmd.fcmd.bus;
		ChipT chip = curEraseCmd.fcmd.chip;
		BlockT block = truncate(curEraseCmd.fcmd.block);

		let addr = {curEraseCmd.card, bus, chip, block} >> valueOf(BlkInfoSelSz);
		blkinfo.portA.request.put (
			// BRAMRequestBE{writeen: 0, responseOnWrite: False, address: truncate(addr), datain: ?}
			BRAMRequest{write: False, responseOnWrite: False, address: truncate(addr), datain: ?}
		);

		phaseErase <= 2;
	endrule

	rule procMapFlashErase2 ( procQ.first.op == ERASE_BLOCK && phaseErase == 2 );
		if(verbose) $display("erase2, %d", cnt);
		let blkinfo_vec <- blkinfo.portA.response.get;

		BusT bus = curEraseCmd.fcmd.bus;
		ChipT chip = curEraseCmd.fcmd.chip;
		BlockT block = truncate(curEraseCmd.fcmd.block);

		let addr = {curEraseCmd.card, bus, chip, block} >> valueOf(BlkInfoSelSz);

		BlkInfoSelT sel = truncate(block);
		blkinfo_vec[sel] = BlkInfoEntry{status: FREE_BLK, erase: blkinfo_vec[sel].erase+1};

		blkinfo.portA.request.put (
			// BRAMRequestBE{writeen: '1, responseOnWrite: False, address: truncate(addr), datain: blkinfo_vec}
			BRAMRequest{write: True, responseOnWrite: False, address: truncate(addr), datain: blkinfo_vec}
		);

		procQ.deq;
		phaseErase <= 0;
	endrule

	Reg#(Bit#(2)) phaseWrite <- mkReg(0);
	Reg#(MultiFlashCmd) curWriteCmd <- mkRegU;
	Reg#(Bit#(TAdd#(1, TSub#(BlockTSz, BlkInfoSelSz)))) blockScanReqCounter <- mkReg(0);
	Reg#(Bit#(TAdd#(1, TSub#(BlockTSz, BlkInfoSelSz)))) blockScanRespCounter <- mkReg(0);
	Reg#(Bit#(TAdd#(1, BlkInfoSelSz))) blockScanFinalCounter <- mkReg(0);
	Bit#(TAdd#(1, TSub#(BlockTSz, BlkInfoSelSz))) max_block_scan_req = fromInteger(valueOf(TExp#(TSub#(BlockTSz, BlkInfoSelSz))));

	// <blk_num, pe cnt> pair
	Reg#(Vector#(BlkInfoEntriesPerWord, Maybe#(Tuple2#(Bit#(14), Bit#(14))))) minEntries <- mkRegU;
	Reg#(Maybe#(Tuple2#(Bit#(14), Bit#(14)))) theMinEntry <- mkRegU;

	function a fromMaybe2(Maybe#(a) b);
		return fromMaybe(?, b);
	endfunction

	function Maybe#(Tuple2#(Bit#(14), Bit#(14))) updateMinEntries (Maybe#(Tuple2#(Bit#(14), Bit#(14))) prevMin, BlkInfoEntry blkEntry, Integer idx);
		if (blkEntry.status != FREE_BLK)
			return prevMin;
		else begin
			//compare only if FREE_BLK
			Bit#(14) minBlk = (zeroExtend( blockScanRespCounter ) << valueOf(BlkInfoSelSz)) + fromInteger(idx);
			//if(verbose) $display("[func] ");
			case ( isValid(prevMin) && tpl_2(fromMaybe2(prevMin)) <= blkEntry.erase )
				True:  return prevMin;
				False: return tagged Valid tuple2( minBlk , blkEntry.erase);
			endcase
		end
	endfunction

	function Maybe#(Tuple2#(Bit#(14), Bit#(14))) getMinEntries (Maybe#(Tuple2#(Bit#(14), Bit#(14))) prevMin, Maybe#(Tuple2#(Bit#(14), Bit#(14))) nextMin);
		if (isValid (nextMin)) begin
			if (isValid(prevMin)) begin
				return (tpl_2(fromMaybe2(prevMin))<=tpl_2(fromMaybe2(nextMin)))?prevMin:nextMin;
			end
			else begin
				return nextMin;
			end
		end
		else begin
			return prevMin;
		end
	endfunction

	rule procMapFlashWrite0 ( procQ.first.op == WRITE_PAGE && phaseWrite == 0 );
		if(verbose) $display("write0, %d", cnt);
		let mapEntry <- map.portA.response.get;
		let lpa = procQ.first.lpa;

		let oneFlashCmd = FlashCmd {
			tag: procQ.first.tag,
			op: WRITE_PAGE,
			bus: truncate( lpa >> valueOf(TLog#(NUM_CARDS)) ),
			chip: truncate( {getSegmentT(lpa), getVirtBlkT(lpa)} >> valueOf(TLog#(TMul#(NUM_BUSES, NUM_CARDS))) ),
			block: zeroExtend( mapEntry.block ),
			page: zeroExtend( getPageT(lpa) )
		};

		let multiFlashCmd = MultiFlashCmd{
			card: lpa[0], // IF one card, could be wrong value but ignored
			fcmd: oneFlashCmd
		};

		case (mapEntry.status)
			NOT_ALLOCATED: begin // TODO: allocation
				curWriteCmd <= multiFlashCmd;
				phaseWrite <= 1;
				blockScanReqCounter <= 0;
				blockScanRespCounter <= 0;
				blockScanFinalCounter <= 0;
				theMinEntry <= tagged Invalid;
				minEntries <= replicate ( tagged Invalid );
			end
			ALLOCATED: begin // We assume SW issues write in append-only manner - we don't check
				procQ.deq;
				respQ.enq(multiFlashCmd);
			end
			default: begin
				procQ.deq;
				resp_errorQ.enq(procQ.first);
			end
		endcase
	endrule

	rule procMapFlashWrite1req ( procQ.first.op == WRITE_PAGE && phaseWrite == 1 && blockScanReqCounter < max_block_scan_req );
		if(verbose) $display("write1req, %d", cnt);
		blockScanReqCounter <= blockScanReqCounter + 1;

		BusT bus = curWriteCmd.fcmd.bus;
		ChipT chip = curWriteCmd.fcmd.chip;
		Bit#(TSub#(BlockTSz, BlkInfoSelSz)) block_upper = truncate(blockScanReqCounter);

		// card (optional, will be truncated), bus, chip, block_upper bits
		let addr = {curWriteCmd.card, bus, chip, block_upper};

		blkinfo.portA.request.put (
			//BRAMRequestBE{writeen: 0, responseOnWrite: False, address: truncate(addr), datain: ?}
			BRAMRequest{write: False, responseOnWrite: False, address: truncate(addr), datain: ?}
		);
	endrule

	rule procMapFlashWrite1resp ( procQ.first.op == WRITE_PAGE && phaseWrite == 1 && blockScanRespCounter < max_block_scan_req );
		if(verbose) $display("write1resp, %d", cnt);
		blockScanRespCounter <= blockScanRespCounter + 1;
		let blkinfo_vec <- blkinfo.portA.response.get;

		let newMinEntries = zipWith3( updateMinEntries, minEntries, blkinfo_vec, genVector() );
		minEntries <= newMinEntries;
	endrule

	rule procMapFlashWrite1post1 ( procQ.first.op == WRITE_PAGE && phaseWrite == 1 && blockScanReqCounter == max_block_scan_req && blockScanRespCounter == max_block_scan_req && blockScanFinalCounter < fromInteger(valueOf(BlkInfoEntriesPerWord)) );
		if(verbose) $display("write1post1, %d", cnt);

		blockScanFinalCounter <= blockScanFinalCounter + 1 ;

		minEntries <= rotate(minEntries); // shift
		theMinEntry <= getMinEntries(theMinEntry, minEntries[0]);
	endrule


	rule procMapFlashWrite1post2 ( procQ.first.op == WRITE_PAGE && phaseWrite == 1 && blockScanReqCounter == max_block_scan_req && blockScanRespCounter == max_block_scan_req && blockScanFinalCounter == fromInteger(valueOf(BlkInfoEntriesPerWord)) );
		if(verbose) $display("write1post2, %d", cnt);
		if (isValid(theMinEntry)) begin
			phaseWrite <= 2;

			BusT bus = curWriteCmd.fcmd.bus;
			ChipT chip = curWriteCmd.fcmd.chip;
			BlockT block = truncate(tpl_1(fromMaybe2(theMinEntry)));
			let erase = tpl_2(fromMaybe2(theMinEntry));

			Bit#(TSub#(BlockTSz, BlkInfoSelSz)) block_upper = truncateLSB( block );
			Bit#(BlkInfoSelSz) block_lower = truncate( block );

			// card (optional, will be truncated), bus, chip, block_upper bits
			let addr_blkinfo = {curWriteCmd.card, bus, chip, block_upper};

			blkinfo.portA.request.put (
				BRAMRequest{ write: False, responseOnWrite: False, address: truncate(addr_blkinfo), datain: ?}
			);

			//Bit#(TDiv#(TMul#(SizeOf#(BlkInfoEntry), BlkInfoEntriesPerWord), 8)) mask = 'b11;
			//mask = mask << {block_lower, 1'b0};
			//let blkEntry = BlkInfoEntry{status: CLEAN_BLK, erase: erase};
			//blkinfo.portA.request.put (
			//	BRAMRequestBE{ writeen: mask, responseOnWrite: False, address: truncate(addr_blkinfo), datain: replicate(blkEntry) }
			//);

			let mapEntry = MapEntry{status: ALLOCATED, block: zeroExtend(block)};
			let addr_map = { getSegmentT(procQ.first.lpa), getVirtBlkT(procQ.first.lpa) };

			map.portA.request.put ( 
				BRAMRequest{ write: True, responseOnWrite: False, address: addr_map, datain: mapEntry }
			);

		end
		else begin
			phaseWrite <= 0;
			procQ.deq;
			resp_errorQ.enq(procQ.first);
		end
	endrule

	rule procMapFlashWrite2 ( procQ.first.op == WRITE_PAGE && phaseWrite == 2 );
		if(verbose) $display("write2, %d", cnt);
		procQ.deq;
		phaseWrite <= 0;

		let blkinfo_vec <- blkinfo.portA.response.get;

		BusT bus = curWriteCmd.fcmd.bus;
		ChipT chip = curWriteCmd.fcmd.chip;
		BlockT block = truncate(tpl_1(fromMaybe2(theMinEntry)));
		let erase = tpl_2(fromMaybe2(theMinEntry));

		Bit#(TSub#(BlockTSz, BlkInfoSelSz)) block_upper = truncateLSB( block );
		Bit#(BlkInfoSelSz) block_lower = truncate( block );

		// card (optional, will be truncated), bus, chip, block_upper bits
		let addr_blkinfo = {curWriteCmd.card, bus, chip, block_upper};

		let updatedEntry = BlkInfoEntry{status: CLEAN_BLK, erase: erase};
		blkinfo_vec[block_lower] = updatedEntry;

		blkinfo.portA.request.put (
			BRAMRequest{ write: True, responseOnWrite: False, address: truncate(addr_blkinfo), datain: blkinfo_vec}
		);

		let response = curWriteCmd;
		response.fcmd.block = extend(block);
		respQ.enq(response);
	endrule

	interface translateReq = toPut(reqQ);
	interface resp = toGet(respQ);
	interface respError = toGet(resp_errorQ);
	interface map_portB = map.portB;
	interface blkinfo_portB = blkinfo.portB;
endmodule
