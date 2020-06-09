`include "ConnectalProjectConfig.bsv"

import FIFOF::*;
import FIFO::*;
import RegFile::*;
import FIFOLevel::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

import Vector::*;
import List::*;
import BuildVector::*;

import ConnectalMemory::*;
import ConnectalConfig::*;
import ConnectalMemTypes::*;
import HostInterface::*;
import MemReadEngine::*;
import MemWriteEngine::*;
import Pipe::*;
import Leds::*;

import Clocks :: *;
import Xilinx       :: *;
`ifndef BSIM
import XilinxCells ::*;
`endif

import AuroraCommon::*;
import ControllerTypes::*;
import FlashCtrl::*;
import FlashCtrlModel::*;

import DualFlashTypes::*;

typedef 8 CmdQDepthR; // 4 does not achieve full speed (848MB/s with 8/6, 833MB/s with 4)
typedef 4 CmdQDepthW;

`ifdef RdEnginePerCard
typedef `RdEnginePerCard RdEnginePerCard;
`else
typedef 4 RdEnginePerCard;
`endif

interface FlashRequest;
	method Action readPage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action writePage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action eraseBlock(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) tag);

	method Action setDmaReadRef(Bit#(32) sgId);
	method Action setDmaWriteRef(Bit#(32) sgId);

	method Action start(Bit#(32) dummy);
	method Action debugDumpReq(Bit#(32) card);
	method Action setDebugVals (Bit#(32) flag, Bit#(32) debugDelay); 
endinterface

interface FlashIndication;
	method Action readDone(Bit#(32) tag);
	method Action writeDone(Bit#(32) tag);
	method Action eraseDone(Bit#(32) tag, Bit#(32) status);
	method Action debugDumpResp(Bit#(32) debug0, Bit#(32) debug1, Bit#(32) debug2, Bit#(32) debug3, Bit#(32) debug4, Bit#(32) debug5);
endinterface

typedef 128 DmaBurstBytes;
typedef 8192 PageSize8192;

typedef TDiv#(DmaBurstBytes, TDiv#(DataBusWidth, 8)) DmaBurstBeats; // 128 / (256/8) = 128 / 32 = 4
typedef TLog#(DmaBurstBeats) DmaBurstBeatsSz; // 2

Integer dmaBurstBytes = valueOf(DmaBurstBytes);
Integer pageSize8192 = valueOf(PageSize8192);

Integer busWidthBytes = valueOf(DataBusWidth)/8; // 32B = 256bit
Integer dmaBurstBeats = valueOf(DmaBurstBeats);
Integer dmaBurstsPer8192Page = (pageSize8192+dmaBurstBytes-1)/dmaBurstBytes; // 64 128B-bursts per 8192B page

// Integer dmaBurstsPerUserPage = (pageSizeUser+dmaBurstBytes-1)/dmaBurstBytes; // 65 128B-bursts per 8224B page
// Integer dmaBurstBeatsLast = (pageSizeUser%dmaBurstBytes)/dmaBurstBytes; //num bursts in last dma; 2(1) bursts

// SW uses only 8192 bytes
Integer wordsPerFlashPage = pageSizeUser/wordBytes; // 8224/16 = 514
Integer wordsPer8192Page  = pageSize8192/wordBytes; // 8192/16 = 512

Integer beatsPerFlashPage = pageSizeUser/busWidthBytes; // 8224/32 = 257
Integer beatsPer8192Page  = pageSize8192/busWidthBytes; // 8192/32 = 256

Integer realBurstsPerPage = pageSize8192/dmaBurstBytes; // 64

Integer padDmaExtra = busWidthBytes; // Send extra 32B instead of indication

Integer dmaAllocPageSizeLog = 14; //typically portal alloc page size is 16KB; MUST MATCH SW

interface MainIfc;
	interface FlashRequest request;
	interface Vector#(1, MemWriteClient#(DataBusWidth)) dmaWriteClient;
	interface Vector#(1, MemReadClient#(DataBusWidth)) dmaReadClient;
	interface Top_Pins pins;
endinterface

`ifdef IMPORT_HOSTIF
module mkMain#(HostInterface host, FlashIndication indication)(MainIfc);
	Clock init_clock = host.derivedClock;
	Reset init_reset = host.derivedReset;
`else
module mkMain#(Clock derivedClock, Reset derivedReset, FlashIndication indication)(MainIfc);
	Clock init_clock = derivedClock;
	Reset init_reset = derivedReset;
`endif

	Reg#(Bool) started <- mkReg(False);
	Reg#(Bit#(64)) cycleCnt <- mkReg(0);

	FIFO#(DualFlashCmd) flashCmdQ <- mkFIFO; // FIFO 16 on Main FPGA / 128 on Artix FPGA
	Vector#(NumTags, Reg#(BusT)) tag2busTable <- replicateM(mkRegU());

	// Offset - pointer
	// Vector#(NumTags, Reg#(Bit#(32))) dmaWriteOffset <- replicateM(mkRegU());
	// Vector#(NumTags, Reg#(Bit#(32))) dmaReadOffset <- replicateM(mkRegU());

	//--------------------------------------------
	// Flash Controller
	//--------------------------------------------
	Vector#(2, GtClockImportIfc) gt_clk_fmcs <- replicateM(mkGtClockImport);
	Vector#(2, FlashCtrlIfc) flashCtrls;
	`ifdef BSIM
		flashCtrls[0] <- mkFlashCtrlModel(gt_clk_fmcs[0].gt_clk_p_ifc, gt_clk_fmcs[0].gt_clk_n_ifc, init_clock, init_reset);
		`ifdef TWO_FLASH_CARDS
		flashCtrls[1] <- mkFlashCtrlModel(gt_clk_fmcs[1].gt_clk_p_ifc, gt_clk_fmcs[1].gt_clk_n_ifc, init_clock, init_reset);
		`endif
	`else
		flashCtrls[0] <- mkFlashCtrl0(gt_clk_fmcs[0].gt_clk_p_ifc, gt_clk_fmcs[0].gt_clk_n_ifc, init_clock, init_reset);
		`ifdef TWO_FLASH_CARDS
		flashCtrls[1] <- mkFlashCtrl1(gt_clk_fmcs[1].gt_clk_p_ifc, gt_clk_fmcs[1].gt_clk_n_ifc, init_clock, init_reset);
		`endif
	`endif

	//--------------------------------------------
	// DMA Module Instantiation
	//--------------------------------------------
	MemWriteEngine#(DataBusWidth, DataBusWidth, CmdQDepthW, TMul#(NUM_CARDS, NUM_BUSES)) we <- mkMemWriteEngineBuff(valueOf(CmdQDepthW)*dmaBurstBytes);
	MemReadEngine#(DataBusWidth, DataBusWidth, CmdQDepthR, TMul#(NUM_CARDS, RdEnginePerCard)) re <- mkMemReadEngineBuff(valueOf(CmdQDepthR)*dmaBurstBytes);

	function MemWriteEngineServer#(DataBusWidth) getWEServer(MemWriteEngine#(DataBusWidth, DataBusWidth, CmdQDepthW, TMul#(NUM_CARDS, NUM_BUSES)) wengine, Integer card, Integer bus);
		return wengine.writeServers[ card + bus*valueOf(NUM_CARDS) ];
	endfunction

	function MemReadEngineServer#(DataBusWidth) getREServer(MemReadEngine#(DataBusWidth, DataBusWidth, CmdQDepthR, TMul#(NUM_CARDS, RdEnginePerCard)) rengine, Integer card, Integer eng);
		return rengine.readServers[ card + eng*valueOf(NUM_CARDS) ];
	endfunction

	function Bit#(32) calcDmaPageOffset(TagT tag);
		Bit#(32) off = zeroExtend(tag);
		return (off<< dmaAllocPageSizeLog);
	endfunction

	rule incCycle;
		cycleCnt <= cycleCnt + 1;
	endrule

	rule driveFlashCmd; // (started);
		let cmd = flashCmdQ.first.fcmd;
		flashCmdQ.deq;
		tag2busTable[cmd.tag] <= cmd.bus;
		flashCtrls[flashCmdQ.first.card].user.sendCmd(cmd); //forward cmd to flash ctrl

		// $display("@%d: Main.bsv: received cmd tag=%d Card%d @%x %x %x %x", 
		//				cycleCnt, cmd.tag, flashCmdQ.first.card, cmd.bus, cmd.chip, cmd.block, cmd.page);
	endrule

	Vector#(2, Reg#(Bit#(32))) debugReadCnt <- replicateM(mkReg(0));
	Vector#(2, Reg#(Bit#(32))) debugWriteCnt <- replicateM(mkReg(0));


	//--------------------------------------------
	// Reads from Flash (DMA Write)
	//--------------------------------------------
	Reg#(Bit#(32)) dmaWriteSgid <- mkReg(0);
	Vector#(NUM_CARDS, Vector#(NUM_BUSES, FIFOF#(TagT))) dmaWriteDoneQs <- replicateM(replicateM(mkFIFOF));

	for (Integer c=0; c<valueOf(NUM_CARDS); c=c+1) begin

		FIFO#(Tuple2#(Bit#(WordSz), TagT)) dataFlash2DmaQ <- mkFIFO();
		Vector#(NUM_BUSES, FIFO#(Tuple2#(Bit#(DataBusWidth), TagT))) dmaWriteBuf <- replicateM(mkFIFO);

		rule doEnqReadFromFlash;
			let taggedRdata <- flashCtrls[c].user.readWord();

			debugReadCnt[c] <= debugReadCnt[c] + 1;
			dataFlash2DmaQ.enq(taggedRdata);
		endrule

		Vector#(NUM_BUSES, Reg#(Bit#(WordSz))) readBufs <- replicateM(mkRegU);
		Vector#(NUM_BUSES, Reg#(Bit#(1))) pageWordCnts <- replicateM(mkReg(0));

		rule doDistributeReadFromFlash;
			let taggedRdata = dataFlash2DmaQ.first;
			dataFlash2DmaQ.deq;
			let tag = tpl_2(taggedRdata);
			let data = tpl_1(taggedRdata);
			BusT bus = tag2busTable[tag];

			readBufs[bus] <= data;
			pageWordCnts[bus] <= pageWordCnts[bus] + 1;

			if ( pageWordCnts[bus] == 1)
				dmaWriteBuf[bus].enq(tuple2({data, readBufs[bus]}, tag));
			// $display("@%d Main.bsv: rdata tag=%d, bus=%d, data[%d,%d]=%x", cycleCnt, tag, bus,dmaWBurstPerPageCnts[bus], dmaWBurstCnts[bus], data);
		endrule

		for (Integer b=0; b<valueOf(NUM_BUSES); b=b+1) begin

			FIFO#(Tuple2#(Bit#(DataBusWidth), TagT)) dmaWriteBufOut <- mkSizedFIFO(dmaBurstBeats); // TODO: maybe just mkFIFO?
			FIFO#(Tuple2#(TagT, Bit#(8))) dmaWriteReqQ <- mkFIFO;
			FIFO#(Bool) dmaWrReq2RespQ <- mkSizedFIFO(valueOf(CmdQDepthW)); 

			Reg#(Bit#(10)) dmaWrBeatsCnt <- mkReg(0);

			rule doReqDMAStart;
				let taggedRdata2 <- toGet(dmaWriteBuf[b]).get;
				let tag = tpl_2(taggedRdata2);

				Bit#(DmaBurstBeatsSz) beatsInBurst = truncate(dmaWrBeatsCnt);
				Bit#(8) burstCnt = truncate(dmaWrBeatsCnt>>valueOf(DmaBurstBeatsSz));

				if(dmaWrBeatsCnt < fromInteger(beatsPer8192Page)) begin // < 256
					if(beatsInBurst == fromInteger(dmaBurstBeats-1)) begin
						dmaWriteReqQ.enq(tuple2(tag, burstCnt)); // Only when we have data of dmaBurstBytes, we send out the request
					end

					dmaWriteBufOut.enq(taggedRdata2); // forward data
				end
				else if (dmaWrBeatsCnt == fromInteger(beatsPer8192Page)) begin
					dmaWriteReqQ.enq(tuple2(tag, burstCnt));
					dmaWriteBufOut.enq(tuple2(-1, tag)); // signal dma done using 1 beat
				end // drop other flash words beyond

				if(dmaWrBeatsCnt == fromInteger(beatsPerFlashPage-1)) begin
					dmaWrBeatsCnt <= 0;
				end
				else begin
					dmaWrBeatsCnt <= dmaWrBeatsCnt + 1;
				end
			endrule

			//initiate dma pipeline
			FIFO#(Tuple3#(TagT, Bit#(32), Bool)) dmaWriteReqPipe <- mkFIFO;
			rule initiateDmaWritePipe;
				dmaWriteReqQ.deq;
				let tag = tpl_1(dmaWriteReqQ.first);
				let burstCnt = tpl_2(dmaWriteReqQ.first);
				//let offset = dmaWriteOffset[tag] + ( zeroExtend(burstCnt)<<log2(dmaBurstBytes) );
				let offset = calcDmaPageOffset(tag) + ( zeroExtend(burstCnt)<<log2(dmaBurstBytes) );
				Bool last = (burstCnt == fromInteger(dmaBurstsPer8192Page));
				dmaWriteReqPipe.enq(tuple3(tag,offset,last));
				// $display("[@%d] card%d bus%d tag%d burstCnt%d offset%d last%d: offset calc", cycleCnt, c, b, tag, burstCnt, offset, last?1:0);
			endrule

			//initiate dma
			rule initiateDmaWrite;
				dmaWriteReqPipe.deq;
				let tag = tpl_1(dmaWriteReqPipe.first);
				let offset = tpl_2(dmaWriteReqPipe.first);
				let last = tpl_3(dmaWriteReqPipe.first);

				let dmaCmd = MemengineCmd {
									sglId: dmaWriteSgid, 
									base: zeroExtend(offset),
									len:last?fromInteger(padDmaExtra):fromInteger(dmaBurstBytes), 
									burstLen:last?fromInteger(padDmaExtra):fromInteger(dmaBurstBytes)
								};

				let weS = getWEServer(we, c, b);
				weS.request.put(dmaCmd);
				dmaWrReq2RespQ.enq(last);
				
				// $display("[@%d] dma write req issued tag%d, card%d, bus%d, last%d, base=0x%x, offset=%d",
				//				cycleCnt, tag, c, b, last?1:0, dmaWriteSgid, offset);
			endrule

			Reg#(Bit#(DmaBurstBeatsSz)) dmaWriteBeatCnt <- mkReg(0);
			rule sendDmaWriteData;
				let last = dmaWrReq2RespQ.first;

				Bit#(DmaBurstBeatsSz) thresh = (last)?0:fromInteger(dmaBurstBeats-1);
				if (dmaWriteBeatCnt == thresh) begin
					dmaWrReq2RespQ.deq;
					dmaWriteBeatCnt <= 0;
				end
				else begin
					dmaWriteBeatCnt <= dmaWriteBeatCnt + 1;
				end

				let taggedRdata = dmaWriteBufOut.first;
				dmaWriteBufOut.deq;

				let weS = getWEServer(we, c, b);
				weS.data.enq(tpl_1(taggedRdata));
			endrule

			rule dmaWriteGetResponse;
				let weS = getWEServer(we, c, b);
				let dummy <- weS.done.get;

				/*
				let tag = dmaWrReq2RespQ.first;
				dmaWrReq2RespQ.deq;
				dmaWriteDoneQs[c][b].enq(tag);
				*/
			endrule
		end //for each bus
	end //for each card

/*
	Vector#(TMul#(2, NUM_BUSES), PipeOut#(TagT)) dmaWriteDonePipes = map(toPipeOut, concat(dmaWriteDoneQs));
	FunnelPipe#(1, TMul#(2, NUM_BUSES), TagT, 2) readAckFunnel <- mkFunnelPipesPipelined(dmaWriteDonePipes);
	
	FIFO#(TagT) readAckQ <- mkSizedFIFO(valueOf(NumTags)/2);
	mkConnection(toGet(readAckFunnel[0]), toPut(readAckQ));

	rule sendReadDone;
		let tag <- toGet(readAckQ).get();
		indication.readDone(zeroExtend(tag)); // No more indication
	endrule
*/

	//--------------------------------------------
	// Writes to Flash (DMA Reads)
	//--------------------------------------------
	Reg#(Bit#(32)) dmaReadSgid <- mkReg(0);

	for (Integer c=0; c<valueOf(NUM_CARDS); c=c+1) begin
		FIFO#(Tuple2#(TagT, Bit#(TLog#(RdEnginePerCard)))) wrToDmaReqQ <- mkFIFO();
		Vector#(RdEnginePerCard, FIFO#(TagT)) dmaRdReq2RespQ <- replicateM(mkSizedFIFO(8)); //TODO sz
		Vector#(RdEnginePerCard, FIFO#(TagT)) dmaReadReqQ <- replicateM(mkSizedFIFO(8));

		//Handle write data requests from controller
		Reg#(Bit#(TLog#(RdEnginePerCard))) dmaRBus <- mkReg(0);
		rule handleWriteDataRequestFromFlash;
			TagT tag <- flashCtrls[c].user.writeDataReq();

			// check which bus it's from
			// let bus = tag2busTable[tag];
			// wrToDmaReqQ.enq(tuple2(tag, bus));
			
			// User Round-robin instead
			$display("writeDataReq received card: %d tag: %d assigned to dmaRBus ", c, tag);
			wrToDmaReqQ.enq(tuple2(tag, dmaRBus));
			if (dmaRBus == fromInteger(valueOf(RdEnginePerCard)-1)) begin
				dmaRBus <= 0;
			end
			else begin
				dmaRBus <= dmaRBus + 1;
			end
		endrule

		rule distrDmaReadReq;
			wrToDmaReqQ.deq;
			let r = wrToDmaReqQ.first;
			let tag = tpl_1(r);
			let bus = tpl_2(r);
			dmaReadReqQ[bus].enq(tag);
			dmaRdReq2RespQ[bus].enq(tag);
		endrule

		for (Integer b=0; b<valueOf(RdEnginePerCard); b=b+1) begin
			rule initDmaRead;
				dmaReadReqQ[b].deq;
				let tag = dmaReadReqQ[b].first;

				// let offset = dmaReadOffset[tag];
				let offset = calcDmaPageOffset(tag);
				let dmaCmd = MemengineCmd {
									sglId: dmaReadSgid, 
									base: zeroExtend(offset),
									len:fromInteger(pageSize8192), 
									burstLen:fromInteger(dmaBurstBytes)
								};
				//re.readServers[b].request.put(dmaCmd);
				let reS = getREServer(re, c, b);
				reS.request.put(dmaCmd);

				$display("Main.bsv: dma read cmd issued: tag=%d, base=0x%x, offset=0x%x", tag, dmaReadSgid, offset);
			endrule

			FIFO#(Bit#(WordSz)) rdDataPipe <- mkFIFO;
			Reg#(Bit#(WordSz)) dmaRdUpperWord <- mkRegU;
			Reg#(Bit#(1)) dmaRdIsUpper <- mkReg(0);
			rule aggrDmaRdData;
				dmaRdIsUpper <= dmaRdIsUpper + 1; // toggle
				let wordToFlash = dmaRdUpperWord;

				if(dmaRdIsUpper == 0) begin
					let reS = getREServer(re, c, b);
					let d <- toGet(reS.data).get;
					dmaRdUpperWord <= truncateLSB(d.data);
					wordToFlash = truncate(d.data);
				end
				rdDataPipe.enq(wordToFlash);
			endrule

			FIFO#(Tuple2#(Bit#(WordSz), TagT)) writeWordPipe <- mkFIFO();
			Reg#(Bit#(16)) padCntR <- mkReg(0);
			Reg#(TagT) padTagR <- mkReg(0);
			Reg#(Bit#(32)) dmaRdBeatsCnt <- mkReg(0);
			rule pipeDmaRdData ( padCntR == 0 );
				let d = rdDataPipe.first;
				rdDataPipe.deq;
				let tag = dmaRdReq2RespQ[b].first;

				writeWordPipe.enq(tuple2(d,tag));

				if (dmaRdBeatsCnt == fromInteger(wordsPer8192Page-1)) begin
					dmaRdReq2RespQ[b].deq;
					dmaRdBeatsCnt <= 0;

					padCntR <= fromInteger(wordsPerFlashPage - wordsPer8192Page);
					padTagR <= tag;
				end
				else begin
					dmaRdBeatsCnt <= dmaRdBeatsCnt + 1;
				end
			endrule

			rule doPaddingFlash (padCntR > 0);
				writeWordPipe.enq(tuple2(0, padTagR)); // pad 0 to spare
				padCntR <= padCntR-1;
			endrule

			rule forwardDmaRdData;
				writeWordPipe.deq;
				flashCtrls[c].user.writeWord(writeWordPipe.first);
				debugWriteCnt[c] <= debugWriteCnt[c] + 1;
			endrule
		end //for each eng_port
	end //for each card
	


	//--------------------------------------------
	// Writes/Erase Acks
	//--------------------------------------------

	//Handle acks from controller
	Vector#(2, FIFOF#(Tuple2#(TagT, StatusT))) ackQ <- replicateM(mkFIFOF);
	for (Integer c=0; c<valueOf(NUM_CARDS); c=c+1) begin
		rule handleControllerAck;
			let ackStatus <- flashCtrls[c].user.ackStatus();
			ackQ[c].enq(ackStatus);
		endrule
	end

	let ackPipe = map(toPipeOut, ackQ);
	FunnelPipe#(1, NUM_CARDS, Tuple2#(TagT, StatusT), 1) ackFunnel <- mkFunnelPipesPipelined(ackPipe);

	rule indicateControllerAck;
		let ack <- toGet(ackFunnel[0]).get;
		TagT tag = tpl_1(ack);
		StatusT st = tpl_2(ack);
		case (st)
			WRITE_DONE: indication.writeDone(zeroExtend(tag));
			ERASE_DONE: indication.eraseDone(zeroExtend(tag), 0);
			ERASE_ERROR: indication.eraseDone(zeroExtend(tag), 1);
		endcase
	endrule


	//--------------------------------------------
	// Debug
	//--------------------------------------------
	Vector#(2, FIFO#(Bit#(1))) debugReqQ <- replicateM(mkFIFO);

	for (Integer c=0; c<valueOf(NUM_CARDS); c=c+1) begin
		rule doDebugDump;
			// $display("Main.bsv: debug dump request0 received");
			debugReqQ[c].deq;
			let debugCnts = flashCtrls[c].debug.getDebugCnts(); 
			let gearboxSendCnt = tpl_1(debugCnts);         
			let gearboxRecCnt = tpl_2(debugCnts);   
			let auroraSendCntCC = tpl_3(debugCnts);     
			let auroraRecCntCC = tpl_4(debugCnts);  
			indication.debugDumpResp(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC, debugReadCnt[0], debugWriteCnt[0]);
		endrule
	end

	interface FlashRequest request;
		method Action readPage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
			FlashCmd fcmd = FlashCmd{
				tag: truncate(tag),
				op: READ_PAGE,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: truncate(page)
				};

			//flashCmdQ.enq(fcmd);
			flashCmdQ.enq(DualFlashCmd{card: (card==0)?0:1, fcmd: fcmd});
			// dmaWriteOffset[tag] <= offset;
		endmethod
		
		method Action writePage(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
			FlashCmd fcmd = FlashCmd{
				tag: truncate(tag),
				op: WRITE_PAGE,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: truncate(page)
				};

			//flashCmdQ.enq(fcmd);
			flashCmdQ.enq(DualFlashCmd{card: (card==0)?0:1, fcmd: fcmd});
			// dmaReadOffset[tag] <= offset;
		endmethod

		method Action eraseBlock(Bit#(32) card, Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) tag);
			FlashCmd fcmd = FlashCmd{
				tag: truncate(tag),
				op: ERASE_BLOCK,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: 0
				};

			//flashCmdQ.enq(fcmd);
			flashCmdQ.enq(DualFlashCmd{card: (card==0)?0:1, fcmd: fcmd});
		endmethod

		method Action setDmaReadRef(Bit#(32) sgId);
			dmaReadSgid <= sgId;
		endmethod

		method Action setDmaWriteRef(Bit#(32) sgId);
			dmaWriteSgid <= sgId;
		endmethod

		method Action start(Bit#(32) dummy);
			started <= True;
		endmethod

		method Action debugDumpReq(Bit#(32) card);
			if (card == 0) debugReqQ[0].enq(?);
			else debugReqQ[1].enq(?);
		endmethod

		method Action setDebugVals (Bit#(32) flag, Bit#(32) debugDelay) = noAction;
	endinterface //FlashRequest

	interface dmaWriteClient = vec(we.dmaClient);
	interface dmaReadClient = vec(re.dmaClient);

	interface Top_Pins pins;
		interface aurora_fmc1 = flashCtrls[0].aurora;
		interface aurora_clk_fmc1 = gt_clk_fmcs[0].aurora_clk;
`ifdef TWO_FLASH_CARDS
		interface aurora_fmc2 = flashCtrls[1].aurora;
		interface aurora_clk_fmc2 = gt_clk_fmcs[1].aurora_clk;
`endif
	endinterface
endmodule
