import Vector::*;
import FIFO::*;
import FIFOF::*;
import BRAMFIFO::*;
import ClientServer::*;
import ClientServerHelper::*;
import GetPut::*;

import FlashCtrlIfc::*;
import ControllerTypes::*;


interface FlashReadMultiplexLite#(numeric type nUsers, numeric type nSwitches);
	// in-order request/response per channel
	interface Vector#(nUsers, Server#(DualFlashAddr, Bit#(128))) flashReadServers;

	// flash client flash controllers (# Card)
	interface Vector#(nSwitches, FlashCtrlClient) flashClient; // We only have 1 Card; Connects to FlashSwitch0
endinterface

Bool verbose = False;

module mkFlashReadMultiplexLite(FlashReadMultiplexLite#(nUsers, nSwitches)) provisos (Add#(a__, TLog#(nUsers), 7));

	Vector#(nSwitches, FIFO#(FlashCmd)) flashReqQs <- replicateM(mkFIFO);

	// bus Inorder buffers
	Vector#(nSwitches, Vector#(8, FIFOF#(Bit#(128)))) busPageBufs <- replicateM(replicateM(mkSizedBRAMFIFOF(pageWords)));

	Vector#(nUsers, FIFO#(Bit#(128))) pageRespQs <- replicateM(mkFIFO);

	FIFO#(Tuple3#(Bit#(1), Bit#(3), Bit#(TLog#(nUsers)))) outstandingReqQ <- mkSizedFIFO(128);

	Reg#(Bit#(TLog#(PageWords))) beatCnt <- mkReg(0);
	Reg#(Tuple3#(Bit#(1), Bit#(3), Bit#(TLog#(nUsers)))) readMetaReg <- mkRegU();
	rule deqResp;
		let {card, bus, channel} = readMetaReg;
		if (beatCnt == 0) begin
			let v <- toGet(outstandingReqQ).get;
			{card, bus, channel} = v;
			readMetaReg <= v;
		end
		let d <- toGet(busPageBufs[card][bus]).get;
		pageRespQs[channel].enq(d);

		if ( beatCnt < fromInteger(pageWords-1) )
			beatCnt <= beatCnt + 1;
		else beatCnt <= 0;

		if (verbose) $display("flashReadMux deqResp beatCnt = %d, card = %d, bus = %d, channel = %d", beatCnt, card, bus, channel);
	endrule

	function Server#(DualFlashAddr, Bit#(128)) genFlashReadServers(Integer i);
		return (interface Server#(DualFlashAddr, Bit#(128));
					interface Put request;
						method Action put(DualFlashAddr req);
							flashReqQs[req.card].enq(FlashCmd{tag: zeroExtend(req.bus),
															op: READ_PAGE,
															bus: req.bus,
															chip: req.chip,
															block: extend(req.block),
															page: extend(req.page)});
							outstandingReqQ.enq(tuple3(req.card, req.bus, fromInteger(i)));
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
						Bit#(3) busSelect = truncate(tag);
						busPageBufs[i][busSelect].enq(data);
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
