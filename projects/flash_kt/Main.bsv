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
import Xilinx       :: *;
`ifndef BSIM
import XilinxCells ::*;
`endif

import AuroraCommon::*;
import AuroraIntraZcu::*;

import ControllerTypes::*;
import FlashCtrlZcu::*;
import FlashCtrlModel::*;

import LsKtMergeManager::*; // LightStore Keytable Compaction Manager
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

	//method Action doDmaTest(Bit#(32) dummy);
	//method Action setDmaWriteRef2(Bit#(32) sgId);
	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow); // TODO: test
	method Action startPpa(Bit#(32) cntHigh, Bit#(32) cntLow);

	method Action start(Bit#(32) dummy);
	method Action debugDumpReq(Bit#(32) dummy);
	method Action setDebugVals (Bit#(32) flag, Bit#(32) debugDelay); 
endinterface

interface FlashIndication;
	method Action ppaEchoHigh(Bit#(32) ppa); // TODO: test..
	method Action ppaEchoLow(Bit#(32) ppa); // TODO: test..
	method Action readDone(Bit#(32) tag);
	method Action writeDone(Bit#(32) tag);
	method Action eraseDone(Bit#(32) tag, Bit#(32) status);
	method Action debugDumpResp(Bit#(32) debug0, Bit#(32) debug1, Bit#(32) debug2, Bit#(32) debug3, Bit#(32) debug4, Bit#(32) debug5);
endinterface

typedef 128 DmaBurstBytes; 
typedef TLog#(DmaBurstBytes) DmaBurstBytesLog;
Integer dmaBurstBytesLog = valueOf(DmaBurstBytesLog);
Integer pageSize8192 = 8192;

// following numbers are skewed due to page size of 8224 from FLASH***
Integer dmaBurstBytes = valueOf(DmaBurstBytes);
Integer dmaBurstWords = dmaBurstBytes/wordBytes; //128/16 = 8
Integer dmaBurstsPerPage = (pageSizeUser+dmaBurstBytes-1)/dmaBurstBytes; //ceiling, 65
Integer dmaBurstWordsLast = (pageSizeUser%dmaBurstBytes)/wordBytes; //num bursts in last dma; 2 bursts

// SW uses only 8192 bytes
Integer wordsPerFlashPage = pageSizeUser/wordBytes; // 8224/16 = 514
Integer wordsPer8192Page  = pageSize8192/wordBytes; // 8192/16 = 512
Integer realBurstsPerPage = pageSize8192/dmaBurstBytes; // 64

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

	FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(valueOf(NumTags)/2); // TODO: User tag only 64 (remaining 64 for merging)
	Vector#(NumTags, Reg#(BusT)) tag2busTable <- replicateM(mkRegU());

	// Offset - pointer
	Vector#(NumTags, Reg#(Bit#(32))) dmaWriteOffset <- replicateM(mkRegU());
	Vector#(NumTags, Reg#(Bit#(32))) dmaReadOffset <- replicateM(mkRegU());

	//--------------------------------------------
	// Flash Controller/Switch/Manager
	//--------------------------------------------
	GtClockImportIfc gt_clk_fmc1 <- mkGtClockImport;
	`ifdef BSIM
		FlashCtrlZcuIfc flashCtrl <- mkFlashCtrlModel(gt_clk_fmc1.gt_clk_p_ifc, gt_clk_fmc1.gt_clk_n_ifc, init_clock);
	`else
		FlashCtrlZcuIfc flashCtrl <- mkFlashCtrlZcu(gt_clk_fmc1.gt_clk_p_ifc, gt_clk_fmc1.gt_clk_n_ifc, init_clock);
	`endif

	FlashSwitch#(2) flashSwitch <- mkFlashSwitch; // users[1] for normal IO & users[0,2] for kt-merging
	mkConnection(flashSwitch.flashCtrlClient, flashCtrl.user);

	FlashCtrlUser hostFlashCtrlUser = flashSwitch.users[1];

	FlashReadMultiplex#(2, 1) flashKtReader <- mkFlashReadMultiplex;
	mkConnection(flashKtReader.flashClient[0], flashSwitch.users[0]);

	//--------------------------------------------
	// DMA Module Instantiation
	//--------------------------------------------
	Vector#(NumReadClients, MemReadEngine#(DataBusWidth, DataBusWidth, 8, TDiv#(NUM_ENG_PORTS, `NumReFlash))) re <- replicateM(mkMemReadEngine);
	Vector#(NumWriteClients, MemWriteEngine#(DataBusWidth, DataBusWidth,  1, TDiv#(NUM_ENG_PORTS,`NumWeFlash))) we <- replicateM(mkMemWriteEngine);

	function MemReadEngineServer#(DataBusWidth) getREServer( Vector#(NumReadClients, MemReadEngine#(DataBusWidth, DataBusWidth, 8, TDiv#(NUM_ENG_PORTS, `NumReFlash))) rengine, Integer idx ) ;
		//let numEngineServer = valueOf(TDiv#(NUM_ENG_PORTS,NumReadClients));
		//let idxEngine = idx / numEngineServer;
		//let idxServer = idx % numEngineServer;

		//let idxEngine = idx % valueOf(NumReadClients);
		//let idxServer = idx / valueOf(NumReadClients);
		let idxEngine = idx % (`NumReFlash);
		let idxServer = idx / (`NumReFlash);

		return rengine[idxEngine].readServers[idxServer];
		//return rengine[idx].readServers[0];
	endfunction
	
	function MemWriteEngineServer#(DataBusWidth) getWEServer( Vector#(NumWriteClients, MemWriteEngine#(DataBusWidth, DataBusWidth,  1, TDiv#(NUM_ENG_PORTS,`NumWeFlash))) wengine, Integer idx ) ;
		//let numEngineServer = valueOf(TDiv#(NUM_ENG_PORTS,NumWriteClients));
		//let idxEngine = idx / numEngineServer;
		//let idxServer = idx % numEngineServer;

		let idxEngine = idx % (`NumWeFlash);
		let idxServer = idx / (`NumWeFlash);

		return wengine[idxEngine].writeServers[idxServer];
		//return wengine[idx].writeServers[0];
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


//	//--------------------------------------------
//	// TODO: Test (DMA Write) - Side Band
//	//--------------------------------------------
//	Reg#(Bit#(32)) dmaWriteSgid2 <- mkReg(0);
//	FIFO#(Bool) dmaTestCmdQ <- mkFIFO;
//	FIFO#(Bool) dmaTestReq2RespQ <- mkFIFO;
//
//	rule driveTestDMAReq;
//		dmaTestCmdQ.deq;
//
//		let dmaCmd = MemengineCmd {
//							sglId: dmaWriteSgid2, 
//							base: 0,
//							len:fromInteger(dmaLength), 
//							burstLen:fromInteger(dmaBurstBytes)
//						};
//
//		we[4].writeServers[0].request.put(dmaCmd);
//
//		dmaTestReq2RespQ.enq(True);
//	endrule
//
//	Reg#(Bit#(32)) beatCnt <- mkReg(0);
//	rule driveTestDMAData;
//		let a = dmaTestReq2RespQ.first;
//		if (a == True && beatCnt < 512) beatCnt <= beatCnt+1;
//		else begin
//			beatCnt <= 0;
//			dmaTestReq2RespQ.deq;
//		end
//		
//		we[4].writeServers[0].data.enq('hDEADBEEFABCDEFEF);
//	endrule
//
//	rule driveTestDMADone;
//		let d <- we[4].writeServers[0].done.get;
//		indication.dmaTestDone(11);
//	endrule

	//--------------------------------------------
	// TODO: PPA request test
	//--------------------------------------------
	LsKtMergeManager ktMergeManager <- mkLsKtMergeManager(re[2].readServers, we[4].writeServers);

	// TODO: Tests to be removed
	rule indPPAHigh;
		let d <- ktMergeManager.getPPAHigh;
		indication.ppaEchoHigh(d);
	endrule
	rule indPPALow;
		let d <- ktMergeManager.getPPALow;
		indication.ppaEchoLow(d);
	endrule



	//--------------------------------------------
	// Reads from Flash (DMA Write)
	//--------------------------------------------
	Reg#(Bit#(32)) dmaWriteSgid <- mkReg(0);

	FIFO#(Tuple2#(Bit#(WordSz), TagT)) dataFlash2DmaQ <- mkFIFO();
	Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(Bit#(WordSz), TagT))) dmaWriteBuf <- replicateM(mkSizedFIFO(dmaBurstWords*2)); // mkSizedBRAMFIFO
	Vector#(NUM_ENG_PORTS, FIFO#(Tuple2#(Bit#(WordSz), TagT))) dmaWriteBufOut <- replicateM(mkFIFO());

	//Vector#(NUM_ENG_PORTS, Reg#(Bit#(16))) dmaWBurstCnts <- replicateM(mkReg(0));
	//Vector#(NUM_ENG_PORTS, Reg#(Bit#(16))) dmaWBurstPerPageCnts <- replicateM(mkReg(0));
	Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) wordPerPageCnts <- replicateM(mkReg(0));

	Vector#(NUM_ENG_PORTS, FIFO#(TagT)) dmaWrReq2RespQ <- replicateM(mkFIFO); //TODO: replicateM(mkSizedFIFO(valueOf(NumTags))); //TODO make bigger?
	Vector#(NUM_ENG_PORTS, FIFO#(TagT)) dmaWriteReqQ <- replicateM(mkFIFO);//TODO: replicateM(mkSizedFIFO(valueOf(NumTags)));//TODO make bigger?
	Vector#(NUM_ENG_PORTS, FIFOF#(TagT)) dmaWriteDoneQs <- replicateM(mkFIFOF);

	rule doEnqReadFromFlash;
		if (delayReg==0) begin
			let taggedRdata <- hostFlashCtrlUser.readWord();
			debugReadCnt <= debugReadCnt + 1;
			if (debugFlag==0) begin
				dataFlash2DmaQ.enq(taggedRdata);
			end
			delayReg <= delayRegSet;
		end
		else begin
			delayReg <= delayReg - 1;
		end
	endrule

	Reg#(Bit#(3)) dmaWBus <- mkReg(0);

	rule doDistributeReadFromFlash;
		let taggedRdata = dataFlash2DmaQ.first;
		dataFlash2DmaQ.deq;
		let tag = tpl_2(taggedRdata);
		let data = tpl_1(taggedRdata);
		BusT bus = tag2busTable[tag];
		//let bus = dmaWBus;
		//dmaWBus <= dmaWBus + 1;
		dmaWriteBuf[bus].enq(taggedRdata);
		//$display("@%d Main.bsv: rdata tag=%d, bus=%d, data[%d,%d]=%x", cycleCnt, tag, bus,dmaWBurstPerPageCnts[bus], dmaWBurstCnts[bus], data);
	endrule

	for (Integer b=0; b<valueOf(NUM_ENG_PORTS); b=b+1) begin
		//Reg#(Bit#(16)) padCnt <- mkReg(0);

		//dmaWBurstCnts: counts # of words(128bit, 16Byte) in a dma burst (128Byte): 0~7
		//dmaWBurstPerPageCnts: # of a dma burst in a page (8224B: flash page size): 0~65
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

//		rule collectReadDone;
//			dmaWriteDoneQs[b].deq;
//			let tag = dmaWriteDoneQs[b].first;
//			indication.readDone(zeroExtend(tag));
//		endrule

	end //for each bus

	Vector#(NUM_ENG_PORTS, PipeOut#(TagT)) dmaWriteDonePipes = map(toPipeOut, dmaWriteDoneQs);
	FunnelPipe#(1, NUM_ENG_PORTS, TagT, 2) readAckFunnel <- mkFunnelPipesPipelined(dmaWriteDonePipes);

	FIFO#(TagT) readAckQ <- mkSizedFIFO(valueOf(NumTags)/2); // TODO: User tag only 64 (remaining 64 for merging)
	mkConnection(toGet(readAckFunnel[0]), toPut(readAckQ));

	rule sendReadDone;
		let tag <- toGet(readAckQ).get();
		indication.readDone(zeroExtend(tag));
	endrule



	//--------------------------------------------
	// Writes to Flash (DMA Reads)
	//--------------------------------------------
	Reg#(Bit#(32)) dmaReadSgid <- mkReg(0);

	FIFO#(Tuple2#(TagT, BusT)) wrToDmaReqQ <- mkFIFO();
	Vector#(NUM_ENG_PORTS, FIFO#(TagT)) dmaRdReq2RespQ <- replicateM(mkSizedFIFO(8)); //TODO: replicateM(mkSizedFIFO(valueOf(NumTags))); //TODO sz
	Vector#(NUM_ENG_PORTS, FIFO#(TagT)) dmaReadReqQ <- replicateM(mkFIFO); //TODO: replicateM(mkSizedFIFO(valueOf(NumTags)));
	Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) dmaReadBurstCount <- replicateM(mkReg(0));
	//Vector#(NUM_ENG_PORTS, Reg#(Bit#(32))) dmaRdReqCnts <- replicateM(mkReg(0));

	//Handle write data requests from controller

	Reg#(BusT) dmaRBus <- mkReg(0);
	rule handleWriteDataRequestFromFlash;
		TagT tag <- hostFlashCtrlUser.writeDataReq();
		//check which bus it's from
		let bus = tag2busTable[tag];
		//let bus = dmaRBus;
		//dmaRBus <= dmaRBus + 1;
		wrToDmaReqQ.enq(tuple2(tag, bus));
	endrule

	rule distrDmaReadReq;
		wrToDmaReqQ.deq;
		let r = wrToDmaReqQ.first;
		let tag = tpl_1(r);
		let bus = tpl_2(r);
		dmaReadReqQ[bus].enq(tag);
		dmaRdReq2RespQ[bus].enq(tag);
		//dmaReaders[bus].startRead(tag, fromInteger(pageWords));
	endrule

	for (Integer b=0; b<valueOf(NUM_ENG_PORTS); b=b+1) begin
		rule initDmaRead;
			let tag = dmaReadReqQ[b].first;
			let offset = dmaReadOffset[tag];
			let dmaCmd = MemengineCmd {
								sglId: dmaReadSgid, 
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
		Reg#(Bit#(16)) padCntR <- mkReg(0);
		Reg#(TagT) padTagR <- mkReg(0);
		rule pipeDmaRdData ( padCntR == 0 );
			let d = rdDataPipe.first;
			rdDataPipe.deq;
			let tag = dmaRdReq2RespQ[b].first;

			writeWordPipe.enq(tuple2(d,tag));

			if (dmaReadBurstCount[b] == fromInteger(wordsPer8192Page-1)) begin
				dmaRdReq2RespQ[b].deq;
				dmaReadBurstCount[b] <= 0;

				padCntR <= fromInteger(wordsPerFlashPage - wordsPer8192Page);
				padTagR <= tag;
			end
			else begin
				dmaReadBurstCount[b] <= dmaReadBurstCount[b] + 1;
			end
		endrule

		rule doPaddingFlash (padCntR > 0);
			writeWordPipe.enq(tuple2(0,padTagR)); // pad 0 to spare
			padCntR <= padCntR-1;
		endrule

		rule forwardDmaRdData;
			writeWordPipe.deq;
			hostFlashCtrlUser.writeWord(writeWordPipe.first);
			debugWriteCnt <= debugWriteCnt + 1;
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
		ackQ.deq;
		TagT tag = tpl_1(ackQ.first);
		StatusT st = tpl_2(ackQ.first);
		case (st)
			WRITE_DONE: indication.writeDone(zeroExtend(tag));
			ERASE_DONE: indication.eraseDone(zeroExtend(tag), 0);
			ERASE_ERROR: indication.eraseDone(zeroExtend(tag), 1);
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
		indication.debugDumpResp(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC, debugReadCnt, debugWriteCnt);
	endrule
	
	Vector#(NumWriteClients, MemWriteClient#(DataBusWidth)) dmaWriteClientVec; // = vec(we.dmaClient); 
	Vector#(NumReadClients, MemReadClient#(DataBusWidth)) dmaReadClientVec;

	for (Integer tt = 0; tt < valueOf(NumReadClients); tt=tt+1) begin
		dmaReadClientVec[tt] = re[tt].dmaClient;
	end

	for (Integer tt = 0; tt < valueOf(NumWriteClients); tt=tt+1) begin
		dmaWriteClientVec[tt] = we[tt].dmaClient;
	end

	interface FlashRequest request;
		method Action readPage(Bit#(32) bus, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag, Bit#(32) offset);
			Bit#(6) tag_trunc = truncate(tag);
			FlashCmd fcmd = FlashCmd{
				//tag: truncate(tag),
				tag: zeroExtend(tag_trunc),
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
			Bit#(6) tag_trunc = truncate(tag);
			FlashCmd fcmd = FlashCmd{
				tag: zeroExtend(tag_trunc),
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
			Bit#(6) tag_trunc = truncate(tag);
			FlashCmd fcmd = FlashCmd{
				tag: zeroExtend(tag_trunc),
				op: ERASE_BLOCK,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: 0
				};

			flashCmdQ.enq(fcmd);
		endmethod

//		method Action addDmaReadRefs(Bit#(32) pointer, Bit#(32) offset, Bit#(32) tag);
//			dmaReadRefs[tag] <= tuple2(pointer, offset);
//		endmethod
//
//		method Action addDmaWriteRefs(Bit#(32) pointer, Bit#(32) offset, Bit#(32) tag);
//			dmaWriteRefs[tag] <= tuple2(pointer, offset);
//		endmethod

		method Action setDmaReadRef(Bit#(32) sgId);
			dmaReadSgid <= sgId;
		endmethod

		method Action setDmaWriteRef(Bit#(32) sgId);
			dmaWriteSgid <= sgId;
		endmethod

//		method Action doDmaTest(Bit#(32) dummy);
//			dmaTestCmdQ.enq(True);
//		endmethod
//		method Action setDmaWriteRef2(Bit#(32) sgId);
//			dmaWriteSgid2 <= sgId;
//		endmethod
		method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow);
			ktMergeManager.setDmaKtPPARef(sgIdHigh, sgIdLow, 0);
		endmethod
		method Action startPpa(Bit#(32) cntHigh, Bit#(32) cntLow);
			ktMergeManager.startGetPPA(cntHigh, cntLow);
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
