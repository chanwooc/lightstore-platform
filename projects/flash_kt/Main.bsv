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

import AuroraCommon::*;
import AuroraIntraZcu::*;

import ControllerTypes::*;
import FlashCtrlZcu::*;
import FlashCtrlModel::*;

import LightStoreKtMerger::*; // LightStore Keytable Compaction Manager
import FlashCtrlIfc::*;
import FlashSwitch::*;
import FlashReadMultiplex::*;
`include "ConnectalProjectConfig.bsv"

import Top_Pins::*;

//import MainTypes::*;
typedef 8 NUM_ENG_PORTS;

interface FlashRequest;
	method Action readPage(Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag, Bit#(32) offset);
	method Action writePage(Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag, Bit#(32) offset);
	method Action eraseBlock(Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) tag);

	method Action setDmaReadRef(Bit#(32) sgId);
	method Action setDmaWriteRef(Bit#(32) sgId);

	method Action startCompaction(Bit#(32) cntHigh, Bit#(32) cntLow);
	method Action setDmaKtPpaRef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
	method Action setDmaKtOutputRef(Bit#(32) sgIdKtBuf, Bit#(32) sgIdInvalPPA);

	method Action start(Bit#(32) dummy);
	method Action debugDumpReq(Bit#(32) dummy);
	method Action setDebugVals (Bit#(32) flag, Bit#(32) debugDelay); 
endinterface

interface FlashIndication;
	method Action readDone(Bit#(32) tag);
	method Action writeDone(Bit#(32) tag);
	method Action eraseDone(Bit#(32) tag, Bit#(32) status);
	method Action debugDumpResp(Bit#(32) debug0, Bit#(32) debug1, Bit#(32) debug2, Bit#(32) debug3, Bit#(32) debug4, Bit#(32) debug5);

	method Action mergeDone(Bit#(32) numGenKt, Bit#(32) numInvalAddr, Bit#(64) counter);
	method Action mergeFlushDone1(Bit#(32) num);
	method Action mergeFlushDone2(Bit#(32) num);

// FIXME: indications for testing
//	method Action debug1(Bit#(32) d, Bit#(32) e, Bit#(32) f);
//	method Action debug2(Bit#(32) d);
//	method Action debug3(Bit#(32) d, Bit#(32) e);

//	method Action invalPpaDone(Bit#(32) numInvalPpa);
endinterface

typedef 256 DmaBurstBytes; 
typedef TLog#(DmaBurstBytes) DmaBurstBytesLog;
Integer dmaBurstBytesLog = valueOf(DmaBurstBytesLog);
Integer pageSize8192 = 8192;

// following numbers are skewed due to page size of 8224 from FLASH***
Integer dmaBurstBytes = valueOf(DmaBurstBytes);
Integer dmaBurstWords = dmaBurstBytes/wordBytes; //128/16 = 8 or 256/16 = 16
Integer dmaBurstsPerPage = (pageSizeUser+dmaBurstBytes-1)/dmaBurstBytes; //ceiling, 65 or 33
Integer dmaBurstWordsLast = (pageSizeUser%dmaBurstBytes)/wordBytes; //num bursts in last dma; 2 bursts

// SW uses only 8192 bytes
Integer wordsPerFlashPage = pageSizeUser/wordBytes; // 8224/16 = 514
Integer wordsPer8192Page  = pageSize8192/wordBytes; // 8192/16 = 512
Integer realBurstsPerPage = pageSize8192/dmaBurstBytes; // 64 or 32

Integer dmaAllocPageSizeLog = 13; //typically portal alloc page size is 8KB; MUST MATCH SW
Integer dmaLength = realBurstsPerPage * dmaBurstBytes; // 64 * 128 = 8192
//Integer dmaAllocPageSizeLog = 14; //typically portal alloc page size is 16KB; MUST MATCH SW
//Integer dmaLength = dmaBurstsPerPage * dmaBurstBytes; // 65 * 128 = 8320

interface MainIfc;
	interface FlashRequest request;
	interface Vector#(NumWriteClients, MemWriteClient#(DataBusWidth)) dmaWriteClient;
	interface Vector#(NumReadClients, MemReadClient#(DataBusWidth)) dmaReadClient;
	interface Top_Pins pins;
endinterface

module mkMain#(Clock derivedClock, Reset derivedReset, FlashIndication indication)(MainIfc);
	Clock init_clock = derivedClock;

	Reg#(Bool) started <- mkReg(False);
	Reg#(Bit#(64)) cycleCnt <- mkReg(0);

	FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(4); // virtex has 32 / artix has 128 depth Q
	Vector#(NumTags, Reg#(BusT)) tag2busTable <- replicateM(mkRegU());
	Vector#(TDiv#(NumTags,2), Reg#(BusT)) tag2busTableMerge <- replicateM(mkRegU());

	// Offset - pointer
	Vector#(NumTags, Reg#(Bit#(32))) dmaWriteOffset <- replicateM(mkRegU());
	Vector#(NumTags, Reg#(Bit#(32))) dmaReadOffset <- replicateM(mkRegU());
	Vector#(TDiv#(NumTags,2), Reg#(Bit#(32))) dmaKtMergedOffset <- replicateM(mkRegU());

	//--------------------------------------------
	// Flash Controller/Switch/Manager
	//--------------------------------------------
	GtClockImportIfc gt_clk_fmc1 <- mkGtClockImport;
	`ifdef BSIM
		FlashCtrlZcuIfc flashCtrl <- mkFlashCtrlModel(gt_clk_fmc1.gt_clk_p_ifc, gt_clk_fmc1.gt_clk_n_ifc, init_clock);
	`else
		FlashCtrlZcuIfc flashCtrl <- mkFlashCtrlZcu(gt_clk_fmc1.gt_clk_p_ifc, gt_clk_fmc1.gt_clk_n_ifc, init_clock);
	`endif

	FlashSwitch#(3) flashSwitch <- mkFlashSwitch; // users[1] for normal IO & users[0,2] for kt-merging
	mkConnection(flashSwitch.flashCtrlClient, flashCtrl.user);

	FlashCtrlUser ktWriteUser = flashSwitch.users[1];
	FlashCtrlUser hostFlashCtrlUser = flashSwitch.users[2];

	FlashReadMultiplex#(2, 1) flashKtReader <- mkFlashReadMultiplex;
	mkConnection(flashKtReader.flashClient[0], flashSwitch.users[0]);

	//--------------------------------------------
	// LightStore Compaction Accelerator & DMA Engine
	//--------------------------------------------
	Vector#(TSub#(NumReadClients,`NumReFlash), MemReadEngine#(DataBusWidth, DataBusWidth, 2, 3)) mergeRe <- replicateM(mkMemReadEngine);
	Vector#(TSub#(NumWriteClients, `NumWeFlash), MemWriteEngine#(DataBusWidth, DataBusWidth,  1, 1)) mergeWe <- replicateM(mkMemWriteEngine);

	Vector#(5, MemWriteEngineServer#(DataBusWidth)) mergerWsV;
	mergerWsV = vec(mergeWe[0].writeServers[0], mergeWe[1].writeServers[0], mergeWe[2].writeServers[0], mergeWe[3].writeServers[0], mergeWe[4].writeServers[0]);

	LightStoreKtMerger ktMergeManager <- mkLightStoreKtMerger(mergeRe[0].readServers, mergerWsV, flashKtReader.flashReadServers);

	FIFO#(Bit#(32)) initKtWrite <- mkFIFO;
	FIFOF#(Bit#(32)) ktWriteReqDone <- mkFIFOF;
	FIFO#(Bit#(TLog#(TDiv#(NumTags,2)))) ktWriteTagQ <- mkSizedFIFO(num_tags/2);

	Reg#(Bool) ktWriteQinit <- mkReg(False);
	Reg#(Bit#(TLog#(TDiv#(NumTags,2)))) initQCnt <- mkReg(0);

	rule initKtWriteQ (!ktWriteQinit);
		initQCnt <= initQCnt+1;
		ktWriteTagQ.enq(initQCnt);
		if (initQCnt == fromInteger(num_tags/2 -1))
			ktWriteQinit <= True;
	endrule

	rule mergeDone;
		let {numKt, numInvalAddr, counter} <- ktMergeManager.mergeDone;
		indication.mergeDone(numKt, numInvalAddr, counter);

		initKtWrite.enq(numKt);
	endrule

	Reg#(Bit#(32)) reqSent <- mkReg(0);
	rule driveKtFlashWriteCmd;
		let ktsToFlush = initKtWrite.first;

		let newtag <- toGet(ktWriteTagQ).get;
		let ppa <- ktMergeManager.getPpaDest;
		let addr = toDualFlashAddr(ppa);

//		indication.debug1(ppa, ktsToFlush, reqSent);

		FlashCmd fcmd = FlashCmd{
			tag: zeroExtend(newtag),
			op: WRITE_PAGE,
			bus: addr.bus,
			chip: addr.chip,
			block: extend(addr.block),
			page: extend(addr.page)
		};

		if(reqSent == ktsToFlush-1) begin
			reqSent <= 0;
			initKtWrite.deq;
			ktWriteReqDone.enq(ktsToFlush);
			indication.mergeFlushDone1(0);
		end
		else reqSent <= reqSent + 1;

		dmaKtMergedOffset[newtag] <= (reqSent << dmaAllocPageSizeLog);
		tag2busTableMerge[newtag] <= addr.bus;
		ktWriteUser.sendCmd(fcmd); //forward cmd to flash ctrl
	endrule

	//--------------------------------------------
	// Flash DMA Module Instantiation
	//--------------------------------------------
	Vector#(`NumReFlash, MemReadEngine#(DataBusWidth, DataBusWidth, 8, TDiv#(NUM_ENG_PORTS, `NumReFlash))) re <- replicateM(mkMemReadEngine);
	Vector#(`NumWeFlash, MemWriteEngine#(DataBusWidth, DataBusWidth,  1, TDiv#(NUM_ENG_PORTS,`NumWeFlash))) we <- replicateM(mkMemWriteEngine);

	function MemReadEngineServer#(DataBusWidth) getREServer( Vector#(`NumReFlash, MemReadEngine#(DataBusWidth, DataBusWidth, 8, TDiv#(NUM_ENG_PORTS, `NumReFlash))) rengine, Integer idx ) ;
		let idxEngine = idx % (`NumReFlash);
		let idxServer = idx / (`NumReFlash);

		return rengine[idxEngine].readServers[idxServer];
	endfunction
	
	function MemWriteEngineServer#(DataBusWidth) getWEServer( Vector#(`NumWeFlash, MemWriteEngine#(DataBusWidth, DataBusWidth,  1, TDiv#(NUM_ENG_PORTS,`NumWeFlash))) wengine, Integer idx ) ;
		let idxEngine = idx % (`NumWeFlash);
		let idxServer = idx / (`NumWeFlash);

		return wengine[idxEngine].writeServers[idxServer];
	endfunction

	function Bit#(32) calcDmaPageOffset(TagT tag);
		Bit#(32) off = zeroExtend(tag);
		return (off<< dmaAllocPageSizeLog);
	endfunction

	rule incCycle;
		cycleCnt <= cycleCnt + 1;
	endrule

	rule driveFlashCmd; // (started);
		let cmd = flashCmdQ.first;
		flashCmdQ.deq;
		tag2busTable[cmd.tag] <= cmd.bus;
		hostFlashCtrlUser.sendCmd(cmd); //forward cmd to flash ctrl
		$display("@%d: Main.bsv: received cmd tag=%d @%x %x %x %x", 
						cycleCnt, cmd.tag, cmd.bus, cmd.chip, cmd.block, cmd.page);
	endrule

	Reg#(Bit#(32)) delayRegSet <- mkReg(0);
	Reg#(Bit#(32)) delayReg <- mkReg(0);
	Reg#(Bit#(32)) debugFlag <- mkReg(0);
	Reg#(Bit#(32)) debugReadCnt <- mkReg(0);
	Reg#(Bit#(32)) debugWriteCnt <- mkReg(0);

	//--------------------------------------------
	// Reads from Flash (DMA Write)
	//--------------------------------------------
	Reg#(Bit#(32)) dmaWriteSgid <- mkReg(0);

	FIFO#(Tuple2#(Bit#(WordSz), TagT)) dataFlash2DmaQ <- mkFIFO();
	//Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(Bit#(WordSz), TagT))) dmaWriteBuf <- replicateM(mkSizedBRAMFIFO(dmaBurstWords*2)); 
	Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(Bit#(WordSz), TagT))) dmaWriteBuf <- replicateM(mkSizedBRAMFIFO(dmaBurstWords*8)); 
	Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(Bit#(WordSz), TagT))) dmaWriteBufOut <- replicateM(mkFIFO());

	Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) wordPerPageCnts <- replicateM(mkReg(0));

	Vector#(NUM_ENG_PORTS, FIFO#(TagT)) dmaWrReq2RespQ <- replicateM(mkSizedFIFO(4)); 
	Vector#(NUM_ENG_PORTS, FIFO#(TagT)) dmaWriteReqQ <- replicateM(mkSizedFIFO(4));
	Vector#(NUM_ENG_PORTS, FIFOF#(TagT)) dmaWriteDoneQs <- replicateM(mkFIFOF);

	rule doEnqReadFromFlash;
		let taggedRdata <- hostFlashCtrlUser.readWord();
		dataFlash2DmaQ.enq(taggedRdata);
	endrule

	rule doDistributeReadFromFlash;
		let taggedRdata = dataFlash2DmaQ.first;
		dataFlash2DmaQ.deq;
		let tag = tpl_2(taggedRdata);
		let data = tpl_1(taggedRdata);
		BusT bus = tag2busTable[tag];
		dmaWriteBuf[bus].enq(taggedRdata);
	endrule

	for (Integer b=0; b<valueOf(NUM_ENG_PORTS); b=b+1) begin
		//Reg#(Bit#(16)) padCnt <- mkReg(0);

		//wordPerPageCnts: # of words (128bit, 16Byte) from flash
		rule doReqDMAStart;
			dmaWriteBuf[b].deq;
			let taggedRdata = dmaWriteBuf[b].first;
			let tag = tpl_2(taggedRdata);

			if(wordPerPageCnts[b]==0) begin
				dmaWriteReqQ[b].enq(tag);
			end

			if(wordPerPageCnts[b] < fromInteger(wordsPer8192Page)) begin // < 512
				dmaWriteBufOut[b].enq(taggedRdata);
			end

			if(wordPerPageCnts[b] == fromInteger(wordsPerFlashPage-1)) begin
				wordPerPageCnts[b] <= 0;
			end
			else begin
				wordPerPageCnts[b] <= wordPerPageCnts[b] + 1;
			end
		endrule

		//initiate dma pipeline
		FIFO#(Tuple2#(TagT, Bit#(32))) dmaWriteReqPipe <- mkFIFO;
		//FIFO#(TagT) dmaWriteReqPipe <- mkFIFO;
		rule initiateDmaWritePipe;
			dmaWriteReqQ[b].deq;
			let tag = dmaWriteReqQ[b].first;
			let offset = dmaWriteOffset[tag];
			dmaWriteReqPipe.enq(tuple2(tag,offset));
		endrule

		//initiate dma
		rule initiateDmaWrite;
			dmaWriteReqPipe.deq;
			let tag = tpl_1(dmaWriteReqPipe.first);
			let offset = tpl_2(dmaWriteReqPipe.first);

			let dmaCmd = MemengineCmd {
								sglId: dmaWriteSgid, 
								base: zeroExtend(offset),
								len:fromInteger(dmaLength), 
								burstLen:fromInteger(dmaBurstBytes)
							};

			let weS = getWEServer(we,b);
			weS.request.put(dmaCmd);
			dmaWrReq2RespQ[b].enq(tag);
			
			$display("@%d Main.bsv: init dma write tag=%d, bus=%d, base=0x%x, offset=%x",
							cycleCnt, tag, b, dmaWriteSgid, offset);
		endrule

		Reg#(Bit#(1)) phase <- mkReg(0);
		rule sendDmaWriteData;
			let taggedRdata = dmaWriteBufOut[b].first;
			dmaWriteBufOut[b].deq;

			let weS = getWEServer(we,b);
			weS.data.enq(tpl_1(taggedRdata));
		endrule

		//dma response.get done; when enough has accumulated, send ack to sw
		rule dmaWriteGetResponse;
			let weS = getWEServer(we,b);
			let dummy <- weS.done.get;
			let tag = dmaWrReq2RespQ[b].first;
			dmaWrReq2RespQ[b].deq;
			$display("@%d Main.bsv: dma resp tag=%d", cycleCnt, tag);
			dmaWriteDoneQs[b].enq(tag);
		endrule
	end //for each bus

	Vector#(NUM_ENG_PORTS, PipeOut#(TagT)) dmaWriteDonePipes = map(toPipeOut, dmaWriteDoneQs);
	FunnelPipe#(1, NUM_ENG_PORTS, TagT, 2) readAckFunnel <- mkFunnelPipesPipelined(dmaWriteDonePipes);

	FIFO#(TagT) readAckQ <- mkSizedFIFO(fromInteger(num_tags/2)); 
	mkConnection(toGet(readAckFunnel[0]), toPut(readAckQ));

	rule sendReadDone;
		let tag <- toGet(readAckQ).get();
		indication.readDone(zeroExtend(tag));
	endrule


	//--------------------------------------------
	// Writes to Flash (DMA Reads) for Normal HostIO & Compaction
	//--------------------------------------------
	Reg#(Bit#(32)) dmaReadSgid <- mkReg(0);
	Reg#(Bit#(32)) dmaKtMergedSgid <- mkReg(0);

	FIFO#(Tuple3#(TagT, BusT, Bool)) wrToDmaReqQ <- mkFIFO();
	Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(TagT, Bool))) dmaRdReq2RespQ <- replicateM(mkSizedFIFO(8));
	Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(TagT, Bool))) dmaReadReqQ <- replicateM(mkFIFO);
	Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) dmaReadBurstCount <- replicateM(mkReg(0));
	//Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) dmaRdReqCnts <- replicateM(mkReg(0));

//	Reg#(Bit#(32)) debug2cnt <- mkReg(0);
	rule handleMergedKtDataRequestFromFlash;
		TagT tag <- ktWriteUser.writeDataReq();
		//check which bus it's from
		Bit#(TLog#(TDiv#(NumTags,2))) ttag = truncate(tag);
		let bus = tag2busTableMerge[ttag];
		wrToDmaReqQ.enq(tuple3(tag, bus, False)); // compaction IO

//		debug2cnt <= debug2cnt + 1;
//		indication.debug2(debug2cnt);
	endrule

	//Handle write data requests from controller
	rule handleWriteDataRequestFromFlash1;
		TagT tag <- hostFlashCtrlUser.writeDataReq();
		//check which bus it's from
		let bus = tag2busTable[tag];
		wrToDmaReqQ.enq(tuple3(tag, bus, True)); // host IO
	endrule

	rule distrDmaReadReq;
		wrToDmaReqQ.deq;
		let {tag, bus, hostIO} = wrToDmaReqQ.first;
		dmaReadReqQ[bus].enq(tuple2(tag, hostIO));
		dmaRdReq2RespQ[bus].enq(tuple2(tag, hostIO));
	endrule

	for (Integer b=0; b<valueOf(NUM_ENG_PORTS); b=b+1) begin
		rule initDmaRead;
			let {tag, hostIO} = dmaReadReqQ[b].first;
//			indication.debug3(extend(tag), extend(pack(hostIO)));

			Bit#(TLog#(TDiv#(NumTags,2))) ttag = truncate(tag);
			let offset = (hostIO)?dmaReadOffset[tag]:dmaKtMergedOffset[ttag];
			let dmaCmd = MemengineCmd {
								sglId: (hostIO)?dmaReadSgid:dmaKtMergedSgid, 
								base: zeroExtend(offset),
								len:fromInteger(dmaLength), 
								burstLen:fromInteger(dmaBurstBytes)
							};
			//re.readServers[b].request.put(dmaCmd);
			let reS = getREServer(re,b);
			reS.request.put(dmaCmd);

			$display("Main.bsv: dma read cmd issued: tag=%d, base=0x%x, offset=0x%x", tag, dmaReadSgid, offset);
			dmaReadReqQ[b].deq;
		endrule

		FIFO#(Bit#(WordSz)) rdDataPipe <- mkFIFO;
		rule aggrDmaRdData;
			let reS = getREServer(re,b);
			let d <- toGet(reS.data).get;
			rdDataPipe.enq(d.data);
		endrule

		FIFO#(Tuple2#(Bit#(128), TagT)) writeWordPipe <- mkFIFO();
		FIFO#(Tuple2#(Bit#(128), TagT)) writeWordPipeMerged <- mkFIFO();
		Reg#(Bit#(16)) padCntR <- mkReg(0);
		Reg#(TagT) padTagR <- mkReg(0);
		Reg#(Bit#(16)) padCntRMerged <- mkReg(0);
		Reg#(TagT) padTagRMerged <- mkReg(0);
		rule pipeDmaRdData ( padCntR == 0 );
			let d = rdDataPipe.first;
			rdDataPipe.deq;
			let {tag, hostIO} = dmaRdReq2RespQ[b].first;

			if(hostIO) writeWordPipe.enq(tuple2(d,tag));
			else writeWordPipeMerged.enq(tuple2(d,tag));

			if (dmaReadBurstCount[b] == fromInteger(wordsPer8192Page-1)) begin
				dmaRdReq2RespQ[b].deq;
				dmaReadBurstCount[b] <= 0;

				if(hostIO) begin
					padCntR <= fromInteger(wordsPerFlashPage - wordsPer8192Page);
					padTagR <= tag;
				end
				else begin
					padCntRMerged <= fromInteger(wordsPerFlashPage - wordsPer8192Page);
					padTagRMerged <= tag;
				end
			end
			else begin
				dmaReadBurstCount[b] <= dmaReadBurstCount[b] + 1;
			end
		endrule

		rule doPaddingFlash (padCntR > 0);
			writeWordPipe.enq(tuple2(0,padTagR)); // pad 0 to spare
			padCntR <= padCntR-1;
		endrule

		rule doPaddingKtMergeFlash (padCntRMerged > 0);
			writeWordPipeMerged.enq(tuple2(0,padTagRMerged)); // pad 0 to spare
			padCntRMerged <= padCntRMerged-1;
		endrule

		rule forwardDmaRdData;
			writeWordPipe.deq;
			hostFlashCtrlUser.writeWord(writeWordPipe.first);
			debugWriteCnt <= debugWriteCnt + 1;
		endrule

		rule forwardDmaRdDataMerged;
			writeWordPipeMerged.deq;
			ktWriteUser.writeWord(writeWordPipeMerged.first);
		endrule
	end //for each eng_port


	//--------------------------------------------
	// Writes/Erase Acks
	//--------------------------------------------

	//Handle acks from controller
	FIFO#(Tuple2#(TagT, StatusT)) ackQ <- mkFIFO;
	rule handleControllerAck;
		let ackStatus <- hostFlashCtrlUser.ackStatus();
		ackQ.enq(ackStatus);
	endrule

	rule indicateControllerAck;
		let {tag, status} <- toGet(ackQ).get;
		case (status)
			WRITE_DONE: indication.writeDone(zeroExtend(tag));
			ERASE_DONE: indication.eraseDone(zeroExtend(tag), 0);
			ERASE_ERROR: indication.eraseDone(zeroExtend(tag), 1);
		endcase
	endrule

	FIFO#(Tuple2#(TagT, StatusT)) ackKtQ <- mkFIFO;
	Reg#(Bit#(32)) numKtWritten <- mkReg(0);
	rule handleControllerAckKtMerge;
		let ackStatus <- ktWriteUser.ackStatus();
		ackKtQ.enq(ackStatus);
	endrule

	rule handleControllerAckKtMerge2;
		let {tag, status} <- toGet(ackKtQ).get;
		case (status)
			WRITE_DONE: begin
				ktWriteTagQ.enq(truncate(tag));

				if(ktWriteReqDone.notEmpty&&(numKtWritten==ktWriteReqDone.first-1)) begin
					ktWriteReqDone.deq;
					numKtWritten <= 0;
					indication.mergeFlushDone2(0);
				end
				else begin
					numKtWritten <= numKtWritten + 1;
				end
			end
		endcase
	endrule


	//--------------------------------------------
	// Debug
	//--------------------------------------------
	FIFO#(Bit#(1)) debugReqQ <- mkFIFO();
	rule doDebugDump;
		$display("Main.bsv: debug dump request received");
		debugReqQ.deq;
		let debugCnts = flashCtrl.debug.getDebugCnts(); 
		let gearboxSendCnt = tpl_1(debugCnts);         
		let gearboxRecCnt = tpl_2(debugCnts);   
		let auroraSendCntCC = tpl_3(debugCnts);     
		let auroraRecCntCC = tpl_4(debugCnts);  
		//indication.debugDumpResp(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC, debugReadCnt, debugWriteCnt);
		indication.debugDumpResp(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC, flashSwitch.readCnt, flashSwitch.writeCnt);
	endrule
	
	Vector#(NumWriteClients, MemWriteClient#(DataBusWidth)) dmaWriteClientVec; // = vec(we.dmaClient); 
	Vector#(NumReadClients, MemReadClient#(DataBusWidth)) dmaReadClientVec;

	for (Integer tt = 0; tt < `NumWeFlash; tt=tt+1) begin
		dmaWriteClientVec[tt] = we[tt].dmaClient;
	end
	for (Integer tt = `NumWeFlash; tt < valueOf(NumWriteClients); tt=tt+1) begin
		dmaWriteClientVec[tt] = mergeWe[tt-`NumWeFlash].dmaClient;
	end
	for (Integer tt = 0; tt < `NumReFlash; tt=tt+1) begin
		dmaReadClientVec[tt] = re[tt].dmaClient;
	end
	for (Integer tt = `NumReFlash; tt < valueOf(NumReadClients); tt=tt+1) begin
		dmaReadClientVec[tt] = mergeRe[tt-`NumReFlash].dmaClient;
	end

	interface FlashRequest request;
		method Action readPage(Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag, Bit#(32) offset);
			FlashCmd fcmd = FlashCmd{
				tag: truncate(tag),
				op: READ_PAGE,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: truncate(page)
				};

			flashCmdQ.enq(fcmd);
			dmaWriteOffset[tag] <= offset;
		endmethod
		
		method Action writePage(Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag, Bit#(32) offset);
			FlashCmd fcmd = FlashCmd{
				tag: truncate(tag),
				op: WRITE_PAGE,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: truncate(page)
				};

			flashCmdQ.enq(fcmd);
			dmaReadOffset[tag] <= offset;
		endmethod

		method Action eraseBlock(Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) tag);
			FlashCmd fcmd = FlashCmd{
				tag: truncate(tag),
				op: ERASE_BLOCK,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: 0
				};

			flashCmdQ.enq(fcmd);
		endmethod

		method Action setDmaReadRef(Bit#(32) sgId);
			dmaReadSgid <= sgId;
		endmethod

		method Action setDmaWriteRef(Bit#(32) sgId);
			dmaWriteSgid <= sgId;
		endmethod

		// Compaction related
		method Action startCompaction(Bit#(32) cntHigh, Bit#(32) cntLow);
			ktMergeManager.startCompaction(cntHigh, cntLow);
//			debug2cnt<=0;
		endmethod
		method Action setDmaKtPpaRef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
			ktMergeManager.setDmaKtPpaRef(sgIdHigh, sgIdLow, sgIdRes);
		endmethod
		method Action setDmaKtOutputRef(Bit#(32) sgIdKtBuf, Bit#(32) sgIdInvalPPA);
			ktMergeManager.setDmaKtOutputRef(sgIdKtBuf, sgIdInvalPPA);
			dmaKtMergedSgid <= sgIdKtBuf;
		endmethod

		method Action start(Bit#(32) dummy);
			started <= True;
		endmethod

		method Action debugDumpReq(Bit#(32) dummy);
			debugReqQ.enq(1);
		endmethod

		method Action setDebugVals (Bit#(32) flag, Bit#(32) debugDelay); 
			delayRegSet <= debugDelay;
			debugFlag <= flag;
		endmethod
	endinterface //FlashRequest

	interface dmaWriteClient = dmaWriteClientVec;
	interface dmaReadClient = dmaReadClientVec;

	interface Top_Pins pins;
		interface aurora_fmc1 = flashCtrl.aurora;
		interface aurora_clk_fmc1 = gt_clk_fmc1.aurora_clk;
		interface LEDS leds;
			method Bit#(LedsWidth) leds = flashCtrl.debug.getAuroraStatus;
		endinterface
	endinterface
endmodule
