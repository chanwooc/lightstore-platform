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

import ConnectalMemory::*;
import ConnectalConfig::*;
import ConnectalMemTypes::*;
import MemReadEngine::*;
import MemWriteEngine::*;
import Pipe::*;
import Leds::*;

import Clocks :: *;
import Xilinx       :: *;
import XilinxCells ::*;

import ControllerTypes::*;
import MyTypes::*;

import AFTL::*;

// Custom types for SW-HW communication
typedef enum {
	AmfREAD,
	AmfWRITE,
	AmfERASE,
	AmfINVALID
} AmfCmdTypes deriving (Bits, Eq, FShow);

typedef struct {
	AmfCmdTypes cmd;
	Bit#(7) tag;
	Bit#(27) lpa; // 3-bit bus 3-bit chip 12-bit block 8-bit page + (optional) 1-bit card
} AmfRequest deriving (Bits);

typedef struct {
	AmfCmdTypes cmd;
	Bit#(7) tag;
	Bit#(1) card;
	Bit#(3) bus;
	Bit#(3) chip;
	Bit#(12) block;
	Bit#(8) page;
} AmfFlashRequest deriving (Bits);

interface AftlRequest;
	method Action makeReq(AmfRequest req);
	method Action updateMapping(Bit#(19) seg_virtblk, Bit#(1) allocated, Bit#(14) mapped_block);
	method Action readMapping(Bit#(19) seg_virtblk);
	method Action updateBlkInfo(Bit#(16) phyaddr_upper, Vector#(8, Bit#(16)) blkinfo_vec);
	method Action readBlkInfo(Bit#(16) phyaddr_upper);
endinterface

interface AftlIndication;
	method Action respSuccess(AmfFlashRequest resp);
	method Action respFailed(AmfRequest resp);
	method Action respReadMapping(Bit#(1) allocated, Bit#(14) block_num);
	method Action respReadBlkInfo(Vector#(8, Bit#(16)) blkinfo_vec);
endinterface

interface MainIfc;
	interface AftlRequest request;
	// interface Vector#(NumWriteClients, MemWriteClient#(DataBusWidth)) dmaWriteClient;
	// interface Vector#(NumReadClients, MemReadClient#(DataBusWidth)) dmaReadClient;
endinterface

module mkMain#(AftlIndication indication)(MainIfc);
	let aftl <- mkAFTL128;

	rule driveResp;
		let r <- aftl.resp.get;
		AmfCmdTypes cmd = AmfINVALID;
		case (r.fcmd.op)
			READ_PAGE: cmd = AmfREAD;
			WRITE_PAGE: cmd = AmfWRITE;
			ERASE_BLOCK: cmd = AmfERASE;
		endcase

		indication.respSuccess(
			AmfFlashRequest{ cmd: cmd, tag: r.fcmd.tag, card: r.card, bus: r.fcmd.bus, chip: r.fcmd.chip,
							 block: truncate(r.fcmd.block), page: truncate(r.fcmd.page) }
		);
	endrule

	rule driveRespErr;
		let r <- aftl.respError.get;
		AmfCmdTypes cmd = AmfINVALID;
		case (r.op)
			READ_PAGE: cmd = AmfREAD;
			WRITE_PAGE: cmd = AmfWRITE;
			ERASE_BLOCK: cmd = AmfERASE;
		endcase

		indication.respFailed(
			AmfRequest{ cmd: cmd, tag: r.tag, lpa: r.lpa }
		);
	endrule

	function BlkInfoEntry convertToBlkinfo(Bit#(16) ent);
		BlkStatus new_status = 
			case(ent[15:14])
				2'b00: FREE_BLK;
				2'b01: USED_BLK;
				2'b10: BAD_BLK;
				2'b11: DIRTY_BLK;
			endcase;
		return BlkInfoEntry{status: new_status, erase: truncate(ent)};
	endfunction

	function Bit#(16) convertBlkinfo(BlkInfoEntry entry);
		Bit#(2) new_status = 
			case(entry.status)
				FREE_BLK: 0;
				USED_BLK: 1;
				BAD_BLK: 2;
				DIRTY_BLK: 3;
			endcase;
		return {new_status, entry.erase};
	endfunction

	rule mapReadResp;
		let entry <- aftl.map_portB.response.get;
		indication.respReadMapping(entry.status==ALLOCATED?1:0, entry.block);
	endrule

	rule blkinfoReadResp;
		let entries <- aftl.blkinfo_portB.response.get;

		let vec = map(convertBlkinfo, entries);

		indication.respReadBlkInfo(reverse(vec));
	endrule

	interface AftlRequest request;
		method Action makeReq(AmfRequest req);
			FlashOp op = INVALID;
			case (req.cmd)
				AmfREAD: op = READ_PAGE;
				AmfWRITE: op = WRITE_PAGE;
				AmfERASE: op = ERASE_BLOCK;
			endcase

			aftl.translateReq.put( FTLCmd{ tag: req.tag, op: op, lpa: req.lpa } );
		endmethod
		method Action updateMapping(Bit#(19) seg_virtblk, Bit#(1) allocated, Bit#(14) mapped_block);
			MapStatus new_status = (allocated==1)? ALLOCATED : NOT_ALLOCATED;
			let new_entry = MapEntry{status: new_status, block: mapped_block};
			aftl.map_portB.request.put(
				BRAMRequest{write: True, responseOnWrite: False, address: seg_virtblk, datain: new_entry}
			);
		endmethod
		method Action readMapping(Bit#(19) seg_virtblk);
			aftl.map_portB.request.put(
				BRAMRequest{write: False, responseOnWrite: False, address: seg_virtblk, datain: ?}
			);
		endmethod
		method Action updateBlkInfo(Bit#(16) phyaddr_upper, Vector#(8, Bit#(16)) blkinfo_vec);
			let new_entry = map(convertToBlkinfo, reverse(blkinfo_vec));
			aftl.blkinfo_portB.request.put(
				BRAMRequest{write: True, responseOnWrite: False, address: phyaddr_upper, datain: new_entry}
			);
		endmethod
		method Action readBlkInfo(Bit#(16) phyaddr_upper);
			aftl.blkinfo_portB.request.put(
				BRAMRequest{write: False, responseOnWrite: False, address: phyaddr_upper, datain: ?}
			);
		endmethod
	endinterface
endmodule
