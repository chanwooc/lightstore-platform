import Vector::*;
import FIFO::*;
import FIFOF::*;
import BRAMFIFO::*;
import ClientServer::*;
import ClientServerHelper::*;
import GetPut::*;

import FlashCtrlIfc::*;
import ControllerTypes::*;

typedef 8 ReqPerUser;

interface FlashReadMultiplex#(numeric type nUsers, numeric type nSwitches);
	// in-order request/response per channel
	interface Vector#(nUsers, Server#(DualFlashAddr, Bit#(128))) flashReadServers;
	
	// flash client flash controllers (# Card)
	interface Vector#(nSwitches, FlashCtrlClient) flashClient; // We only have 1 Card; Connects to FlashSwitch0
endinterface

Bool verbose = False;

module mkFlashReadMultiplex(FlashReadMultiplex#(nUsers, nSwitches)) provisos (Add#(a__, TLog#(nUsers), 7));

	Vector#(nSwitches, FIFO#(FlashCmd)) flashReqQs <- replicateM(mkFIFO);
	
	// bus Inorder buffers
	//Vector#(nSwitches, Vector#(8, FIFOF#(Bit#(128)))) busPageBufs <- replicateM(replicateM(mkSizedBRAMFIFOF(pageWords))); // 8224

	// Per user, per Card, per Tag(#Req) reorder buffers
	Vector#(nUsers, Vector#(nSwitches, Vector#(ReqPerUser, FIFOF#(Bit#(128))))) reorderBufs <- replicateM(replicateM(replicateM(mkSizedBRAMFIFOF(pageWords)))); // 8224

	Vector#(nUsers, FIFO#(Bit#(128))) pageRespQs <- replicateM(mkFIFO);
	Vector#(nUsers, FIFO#(Tuple2#(Bit#(1), Bit#(TLog#(ReqPerUser))))) outstandingReqQ <- replicateM(mkSizedFIFO(valueOf(ReqPerUser)));

	Vector#(nUsers, Vector#(nSwitches,FIFO#(Bit#(TLog#(ReqPerUser))))) freeTagQ <- replicateM(replicateM(mkSizedFIFO(valueOf(ReqPerUser))));

	for(Integer i =0; i < valueOf(nUsers); i=i+1) begin
		for(Integer j = 0; j < valueOf(nSwitches); j=j+1) begin
			Reg#(Bit#(TLog#(ReqPerUser))) initCnt <- mkReg(0);
			Reg#(Bool) init <- mkReg(False);
			rule initialize (!init);
				initCnt <= initCnt + 1;
				freeTagQ[i][j].enq(initCnt);
				if (initCnt == fromInteger(valueOf(ReqPerUser) - 1))
					init <= True;
			endrule
		end
	end

	for(Integer i = 0; i < valueOf(nUsers); i=i+1) begin
		Reg#(Bit#(TLog#(PageWords))) beatCnt <- mkReg(0);
		Reg#(Tuple2#(Bit#(1), Bit#(TLog#(ReqPerUser)))) readMetaReg <- mkRegU();
		rule deqResp;
			let {card, tag} = readMetaReg;
			if (beatCnt == 0) begin
				let v <- toGet(outstandingReqQ[i]).get;
				{card, tag} = v;
				readMetaReg <= v;
			end
			let d <- toGet(reorderBufs[i][card][tag]).get;
			pageRespQs[i].enq(d);

			if ( beatCnt < fromInteger(pageWords-1) ) begin  // 514 Beat = 8224 Byte
				beatCnt <= beatCnt + 1; // trimming to 8192 (32B) should happen outside
			end
			else begin
				$display("(%m) ReadMuxReorder, one page read finished (chan=%d, beat=%d)", i, beatCnt);

				beatCnt <= 0;
				freeTagQ[i][card].enq(tag);
			end
		endrule
	end

	//Vector#(nUsers, Vector#(ReqPerUser, Reg#(BusT))) tagBusTable <- replicateM(replicateM(mkReg(0)));
	function Server#(DualFlashAddr, Bit#(128)) genFlashReadServers(Integer i);
		return (interface Server#(DualFlashAddr, Bit#(128));
					interface Put request;
						method Action put(DualFlashAddr req);
							let reqTag <- toGet(freeTagQ[i][req.card]).get;
							TagT tag = zeroExtend(reqTag)+(fromInteger(i)<<valueOf(TLog#(ReqPerUser)));
							flashReqQs[req.card].enq(FlashCmd{tag: tag,
															op: READ_PAGE,
															bus: req.bus,
															chip: req.chip,
															block: extend(req.block),
															page: extend(req.page)});
							outstandingReqQ[i].enq(tuple2(req.card, reqTag));
							//tagBusTable[i][reqTag] <= req.bus;
						  endmethod
					endinterface
					interface Get response = toGet(pageRespQs[i]);
				endinterface);
	endfunction

	function FlashCtrlClient genFlashCtrlClient(Integer i);
		return (interface FlashCtrlClient;
					method ActionValue#(FlashCmd) sendCmd;
						let v <- toGet(flashReqQs[i]).get;
						return v;
					endmethod
					method Action readWord (Tuple2#(Bit#(128), TagT) taggedData); 
						if (verbose) $display("flashreadmux got readWord from card %d ", i, fshow(taggedData));
						let {data, tag} = taggedData;
						Bit#(TLog#(ReqPerUser)) reqTag = truncate(tag);
						Bit#(TLog#(nUsers)) serverSelect = truncate(tag>>valueOf(TLog#(ReqPerUser)));
						//let bus = tagBusTable[serverSelect][reqTag];
						//busPageBufs[i][bus].enq(data);
						reorderBufs[serverSelect][i][reqTag].enq(data);
					endmethod
					// methods below will never fire
					method ActionValue#(Tuple2#(Bit#(128), TagT)) writeWord if (False);
						$display("Error:: (%m) writeWord flash port of %d should not be used!", i);
						$finish;
						return ?;
					endmethod
					method Action writeDataReq(TagT tag) if (False); 
						  $display("Error:: (%m) writeDataReq flash port of %d should not be used!", i);
						  $finish;
					endmethod
					method Action ackStatus (Tuple2#(TagT, StatusT) taggedStatus) if (False); 
						  $display("Error:: (%m) ackStatus flash port of %d should not be used!", i);
						  $finish;
					endmethod
				endinterface);
	endfunction

	interface flashReadServers = genWith(genFlashReadServers);
	interface flashClient = genWith(genFlashCtrlClient);
endmodule
